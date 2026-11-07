import AVFoundation
import Foundation

/// 朗读队列里的一条。
///
/// `audioKey` 指向 `VoicePack` 里的真人音频（`w-<词条id>` 之类）；
/// 有音频就播音频，没有才走服务器合成 / TTS。
/// `rate` 只在需要逐行变速时填（如洗脑：词一个速度、例句另一个速度）；
/// 为 nil 时用循环本身的 rate。
struct SpeechLine: Hashable {
    let text: String
    let audioKey: String?
    let rate: Double?

    init(_ text: String, audioKey: String? = nil, rate: Double? = nil) {
        self.text = text
        self.audioKey = audioKey
        self.rate = rate
    }
}

/// 朗读控制器：单句朗读 + 「洗脑」循环（读 N 遍，可暂停 / 可停）。
///
/// 为什么不用 `Speech` 直接循环：`Speech.swift` 的 `speak` 是"发出去就不管了"，
/// 没有播完回调，循环只能按字数估算等待，长句要么被截断、要么空等。
/// 这里自己拿 `AVSpeechSynthesizerDelegate` 的 didFinish 与
/// `AVAudioPlayerDelegate` 的 didFinishPlaying，读完一条再读下一条。
///
/// 朗读顺序和 `Speech` 一致：本地包音频 → 服务器合成 Nanami → 系统语音，
/// 任何一步失败都静默走下一层。
@MainActor
final class SpeechLoop: NSObject, ObservableObject {

    enum Phase: Equatable {
        case idle
        case speaking
        case paused
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var completedRounds = 0
    @Published private(set) var totalRounds = 0

    private let synthesizer = AVSpeechSynthesizer()
    private var pending: CheckedContinuation<Void, Never>?

    private var audioPlayer: AVAudioPlayer?
    private var audioPending: CheckedContinuation<Void, Never>?

    private var runTask: Task<Void, Never>?
    private var rate: Double = 0.45
    /// 朗读轮次计数：超时兜底只放行自己这一轮，上一轮睡过头的超时不能把下一轮提前放行。
    private var speakEpoch = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isRunning: Bool { phase != .idle }
    var isPaused: Bool { phase == .paused }

    /// 还剩几遍没读（界面上「剩余次数」用它）。
    var remainingRounds: Int {
        max(0, totalRounds - completedRounds)
    }

    // MARK: - 对外接口

    /// 读一句，读完就结束。
    func speak(_ line: SpeechLine, rate: Double) {
        stopLoop()
        self.rate = rate
        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.speakOnce(line)
            self.runTask = nil
        }
    }

    func speak(_ text: String, rate: Double) {
        speak(SpeechLine(text), rate: rate)
    }

    /// 循环朗读：每遍按顺序读 `lines` 里的每一条，一共 `rounds` 遍。
    func startLoop(_ lines: [SpeechLine], rounds: Int, rate: Double) {
        stopLoop()
        let cleaned = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !cleaned.isEmpty, rounds > 0 else { return }

        self.rate = rate
        totalRounds = rounds
        completedRounds = 0
        phase = .speaking

        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for round in 0..<rounds {
                if Task.isCancelled { break }
                await self.waitWhilePaused()
                if Task.isCancelled || self.phase == .idle { break }

                for line in cleaned {
                    if Task.isCancelled { break }
                    await self.waitWhilePaused()
                    if Task.isCancelled || self.phase == .idle { break }
                    await self.speakOnce(line)
                }

                if self.phase == .idle { break }
                self.completedRounds = round + 1
            }
            if !Task.isCancelled {
                self.phase = .idle
            }
            self.runTask = nil
        }
    }

    /// 洗脑按钮：读的时候点一下暂停，暂停时点一下继续。
    func togglePause() {
        switch phase {
        case .speaking:
            phase = .paused
            synthesizer.stopSpeaking(at: .immediate)
            audioPlayer?.stop()
            audioPlayer = nil
            // 播放器 stop 不会触发 delegate 回调，这里直接放行，
            // 循环会在下一句前等在 waitWhilePaused 里。
            finishCurrent()
            finishAudio()
        case .paused:
            phase = .speaking
        case .idle:
            break
        }
    }

    func stopLoop() {
        runTask?.cancel()
        runTask = nil
        phase = .idle
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
        finishCurrent()
        finishAudio()
    }

    // MARK: - 内部

    private func waitWhilePaused() async {
        while phase == .paused && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
    }

    /// 读一条：有真人音频先播音频，没有走服务器合成，都没有才按句读切段走 TTS。
    /// 本行自带 rate 时用本行的，否则用循环的 rate。
    private func speakOnce(_ line: SpeechLine) async {
        let effectiveRate = line.rate ?? rate
        if let audioKey = line.audioKey, let url = VoicePack.url(for: audioKey) {
            if await playLocal(url, rate: effectiveRate) { return }
            // 文件损坏：继续往下走，不拿文件名当朗读内容。
        }
        let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if await playWithServer(trimmed, rate: effectiveRate) { return }
        for piece in SpeechText.split(trimmed) {
            if Task.isCancelled { return }
            await speakTTS(piece, rate: effectiveRate)
        }
    }

    /// 服务器合成一路：先把各段取齐（缓存或联网），再顺序播。
    /// 全部播完返回 true；任何一步失败返回 false，由调用方走系统语音。
    private func playWithServer(_ text: String, rate: Double) async -> Bool {
        let base = Speech.shared.serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return false }
        do {
            let percent = ServerTTS.ratePercent(forSpeechRate: rate)
            let chunks = ServerTTS.chunks(of: text)
            guard !chunks.isEmpty else { return true }
            var datas: [Data] = []
            datas.reserveCapacity(chunks.count)
            for chunk in chunks {
                if Task.isCancelled { return true }
                datas.append(try await fetchServerAudio(chunk, percent: percent))
            }
            for data in datas {
                if Task.isCancelled { return true }
                await waitWhilePaused()
                if Task.isCancelled || phase == .idle { return true }
                await playServerAudio(data)
            }
            return true
        } catch {
            return false
        }
    }

    private func fetchServerAudio(_ chunk: String, percent: Int) async throws -> Data {
        let key = ServerTTSCache.key(text: chunk, voiceID: ServerTTS.nanamiVoiceID, ratePercent: percent)
        if let hit = ServerTTSCache.shared.existing(forKey: key) { return hit }
        let client = ServerTTS(baseURL: Speech.shared.serverBaseURL)
        let data = try await client.audio(text: chunk, voiceID: ServerTTS.nanamiVoiceID, ratePercent: percent)
        return try ServerTTSCache.shared.store(data, forKey: key)
    }

    private func playServerAudio(_ data: Data) async {
        speakEpoch += 1
        let epoch = speakEpoch
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            do {
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                player.prepareToPlay()
                guard player.play() else { throw ServerTTS.Failure.malformedAudio }
                audioPlayer = player
                pending = continuation
                Speech.recordEngine("server")
                // 播放器万一不给 didFinish 回调，按本段时长 + 10 秒兜底。
                armTimeout(seconds: min(20.0, player.duration + 10.0), epoch: epoch, target: .tts)
            } catch {
                // 这一段播不出来：直接放行，不回退系统语音，
                // 避免同一句被两种声音各念一遍。
                continuation.resume()
            }
        }
    }

    private func speakTTS(_ text: String, rate: Double) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Speech.shared.activateSession()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = VoiceCatalog.utteranceVoice()
        utterance.rate = Float(min(max(rate, 0.30), 0.60))
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0

        speakEpoch += 1
        let epoch = speakEpoch
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pending = continuation
            synthesizer.speak(utterance)
            Speech.recordEngine("system")
            // 系统 TTS 偶尔不给 didFinish（切后台、语音包异常）。
            // 兜一个上限，宁可少等一拍，也不能让整个循环永久挂在这里。
            armTimeout(seconds: min(20.0, Double(trimmed.count) * 0.45 + 3.0), epoch: epoch, target: .tts)
        }
    }

    /// 播包里的音频。播起来返回 true；文件损坏返回 false，由调用方继续往下走。
    private func playLocal(_ url: URL, rate: Double) async -> Bool {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        Speech.shared.activateSession()
        player.enableRate = true
        player.rate = Float(min(max(0.55 + rate * 0.6, 0.5), 1.2))
        player.delegate = self
        player.prepareToPlay()
        guard player.play() else { return false }
        audioPlayer = player
        Speech.recordEngine("voicepack")

        speakEpoch += 1
        let epoch = speakEpoch
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            audioPending = continuation
            let seconds = min(60.0, player.duration / Double(max(player.rate, 0.1)) + 2.0)
            armTimeout(seconds: seconds, epoch: epoch, target: .local)
        }
        return true
    }

    /// 超时兜底的放行目标：合成器/服务器音频走 `pending`，本地包音频走 `audioPending`。
    private enum TimeoutTarget {
        case tts
        case local
    }

    /// 超时兜底：只放行自己这一轮（epoch 对得上才放行）。
    private func armTimeout(seconds: Double, epoch: Int, target: TimeoutTarget) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, self.speakEpoch == epoch else { return }
            switch target {
            case .tts: self.finishCurrent()
            case .local: self.finishAudio()
            }
        }
    }

    /// 幂等：didFinish / didCancel / 兜底超时都会调，只放行一次。
    private func finishCurrent() {
        guard let continuation = pending else { return }
        pending = nil
        continuation.resume()
    }

    private func finishAudio() {
        guard let continuation = audioPending else { return }
        audioPending = nil
        audioPlayer?.stop()
        audioPlayer = nil
        continuation.resume()
    }

    /// AVAudioPlayer 的回调不分本地包音频还是服务器音频；
    /// 同一时刻只播一个，看哪个 continuation 在等就放行哪个。
    private func finishAudioPlayback() {
        if audioPending != nil { finishAudio() } else { finishCurrent() }
    }
}

extension SpeechLoop: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.finishCurrent() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.finishCurrent() }
    }
}

extension SpeechLoop: AVAudioPlayerDelegate {

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finishAudioPlayback() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.finishAudioPlayback() }
    }
}
