import AVFoundation
import Foundation

/// 念日文。优先级：**本地真人音频 → 服务器合成 Nanami → 系统高质量语音 → 系统默认语音**。
///
/// 三件事决定了它听起来自不自然：
/// 1. 用哪条语音。`AVSpeechSynthesisVoice(language: "ja-JP")` 拿到的是系统默认档
///    （compact，机械），这里改成走 `VoiceCatalog`，优先设备上的增强 / 高级语音；
/// 2. 断句。长句按句读切开分别合成，段间留一点停顿，别一口气念到底；
/// 3. 有没有真人录音。`VoicePack` 里存了同 key 的音频就直接播音频；
///    没有包音频时走服务器合成 Nanami（和包里同一个声音），服务器失败才走系统语音。
/// 任何一步失败都静默走下一层，不弹窗。
@MainActor
final class Speech: NSObject {
    @MainActor static let shared = Speech()

    /// 上次实际用的引擎，设置页的「上次」行读它。取值：voicepack / server / system。
    static let lastEngineKey = "tts.lastEngine"

    static func recordEngine(_ engine: String) {
        UserDefaults.standard.set(engine, forKey: lastEngineKey)
    }

    /// 服务器合成地址，空 = 跳过服务器。默认填用户自己的代理。
    var serverBaseURL: String = ServerTTS.defaultBaseURL   // 现在是 ""

    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var sessionConfigured = false

    private var player: AVAudioPlayer?
    private var playQueue: [Data] = []
    private var fallbackText = ""
    private var fallbackRate = 0.45
    private var workTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private override init() {
        super.init()
        installAudioSessionObservers()
        #if DEBUG
        if VoiceCatalog.hasNoJapaneseVoice {
            print("[JianRiJi] 系统里没有日语语音，去 设置 → 辅助功能 → 朗读内容 → 声音 → 日语 下一个。")
        }
        #endif
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// 来电 / 插拔耳机后音频会话会被系统 deactivate，不重新激活后续朗读全部无声。
    private func installAudioSessionObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .ended {
                self.sessionConfigured = false
                self.activateSession()
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            self?.sessionConfigured = false
            self?.activateSession()
        })
    }

    var hasJapaneseVoice: Bool { !VoiceCatalog.hasNoJapaneseVoice }

    /// 当前是否还在用默认（机械）档——设置页据此给「下载增强语音」的引导。
    var isUsingCompactVoice: Bool { VoiceCatalog.isUsingCompactVoice }

    /// 打开后台播放的音频会话（随身听连播时需要，Info.plist 里有 UIBackgroundModes: audio）。
    func activateSession() {
        guard !sessionConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            sessionConfigured = true
        } catch {
            #if DEBUG
            print("[JianRiJi] 音频会话配置失败：\(error)")
            #endif
        }
    }

    /// 念一句话。
    /// - Parameters:
    ///   - audioKey: 有本地真人音频时传 `VoicePack` 的 key（如 `w-<词条id>`），会优先播音频。
    func speak(_ text: String, rate: Double = 0.45, audioKey: String? = nil) {
        activateSession()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        fallbackText = trimmed
        fallbackRate = rate

        // 1. 本地真人音频
        if let audioKey, let url = VoicePack.url(for: audioKey) {
            if playLocal(url, rate: rate) { return }
            // 文件损坏：继续往下走，不拿文件名当朗读内容。
        }

        // 2. 服务器合成 Nanami
        let base = serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty {
            let percent = ServerTTS.ratePercent(forSpeechRate: rate)
            let chunks = ServerTTS.chunks(of: trimmed)
            if !chunks.isEmpty {
                // 地址在任务开始前取一次，后台任务里不再读可变属性。
                let baseURL = base
                workTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        var datas: [Data] = []
                        datas.reserveCapacity(chunks.count)
                        for chunk in chunks {
                            if Task.isCancelled { return }
                            datas.append(try await self.fetchAudio(chunk, baseURL: baseURL, percent: percent))
                        }
                        await MainActor.run { self.enqueueAndPlay(datas) }
                    } catch {
                        // 服务器任何一步失败：静默退回系统语音。
                        await MainActor.run { self.speakWithSystemVoice(trimmed, rate: rate) }
                    }
                }
                return
            }
        }

        // 3. 系统语音
        speakWithSystemVoice(trimmed, rate: rate)
    }

    func stop() {
        workTask?.cancel()
        workTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        playQueue.removeAll()
        player?.stop()
        player = nil
        audioPlayer?.stop()
        audioPlayer = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - 服务器合成

    private func fetchAudio(_ text: String, baseURL: String, percent: Int) async throws -> Data {
        let key = ServerTTSCache.key(text: text, voiceID: ServerTTS.nanamiVoiceID, ratePercent: percent)
        if let hit = ServerTTSCache.shared.existing(forKey: key) { return hit }
        let client = ServerTTS(baseURL: baseURL)
        let data = try await client.audio(text: text, voiceID: ServerTTS.nanamiVoiceID, ratePercent: percent)
        return try ServerTTSCache.shared.store(data, forKey: key)
    }

    private func enqueueAndPlay(_ datas: [Data]) {
        guard let first = datas.first else {
            speakWithSystemVoice(fallbackText, rate: fallbackRate)
            return
        }
        playQueue = Array(datas.dropFirst())
        play(first)
    }

    private func play(_ data: Data) {
        do {
            activateSession()
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else { throw ServerTTS.Failure.malformedAudio }
            self.player = player
            Self.recordEngine("server")
            scheduleWatchdog(for: player)
        } catch {
            playQueue.removeAll()
            speakWithSystemVoice(fallbackText, rate: fallbackRate)
        }
    }

    private func playNext() {
        guard !playQueue.isEmpty else {
            player = nil
            return
        }
        play(playQueue.removeFirst())
    }

    /// 兜底：播放器万一不给 didFinish 回调，按本段时长 + 10 秒推进，不让队列卡死。
    private func scheduleWatchdog(for player: AVAudioPlayer) {
        watchdogTask?.cancel()
        let seconds = player.duration + 10.0
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.player === player else { return }
                self.player = nil
                self.playNext()
            }
        }
    }

    // MARK: - 系统语音

    private func speakWithSystemVoice(_ text: String, rate: Double) {
        activateSession()
        let voice = VoiceCatalog.utteranceVoice()
        let pieces = SpeechText.split(text)
        guard !pieces.isEmpty else { return }
        Self.recordEngine("system")

        // AVSpeechSynthesizer 自己会按顺序排队播，不用外部串接。
        for (index, piece) in pieces.enumerated() {
            let utterance = AVSpeechUtterance(string: piece)
            utterance.voice = voice
            utterance.rate = clampedRate(rate)
            utterance.pitchMultiplier = 1.0
            // 段间留一点换气感，第一段不等。
            utterance.preUtteranceDelay = index == 0 ? 0 : 0.08
            synthesizer.speak(utterance)
        }
    }

    private func clampedRate(_ rate: Double) -> Float {
        let bounds = Double(AVSpeechUtteranceMinimumSpeechRate)...Double(AVSpeechUtteranceMaximumSpeechRate)
        let safe = min(max(rate, bounds.lowerBound), bounds.upperBound)
        return Float(safe)
    }

    // MARK: - 本地真人音频

    /// 播包里的音频。播起来返回 true；文件损坏或格式不支持返回 false，由调用方继续往下走。
    private func playLocal(_ url: URL, rate: Double) -> Bool {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        player.enableRate = true
        // TTS 的 rate（0.30~0.60）和 AVAudioPlayer 的 rate（1.0 = 原速）不是一套刻度，
        // 这里换算成 0.73~0.91 倍速，接近正常说话的节奏。
        player.rate = Float(min(max(0.55 + rate * 0.6, 0.5), 1.2))
        player.prepareToPlay()
        guard player.play() else { return false }
        audioPlayer = player
        Self.recordEngine("voicepack")
        return true
    }
}

extension Speech: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.watchdogTask?.cancel()
            self.player = nil
            self.playNext()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.watchdogTask?.cancel()
            self.player = nil
            self.playQueue.removeAll()
            // 已播过的段不再重念，直接停。
        }
    }
}
