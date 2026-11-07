import AVFoundation

/// 朗读：优先走服务器合成 Nanami，任何一步失败都静默退回系统 TTS，不弹窗。
/// 服务器地址为空时只用系统语音。地址由 Store 从 AppSettings 同步过来。
/// 注意：设备上没装日语语音包时，系统会退回默认语言，听感会差一截。
final class Speech: NSObject {
    static let shared = Speech()

    /// 上次实际用的引擎，设置页的「上次」行读它。
    static let lastEngineKey = "tts.lastEngine"

    static func recordEngine(_ engine: String) {
        UserDefaults.standard.set(engine, forKey: lastEngineKey)
    }

    /// 服务器合成地址，空 = 只用系统语音。默认填用户自己的代理。
    var serverBaseURL: String = ServerTTS.defaultBaseURL

    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "ja-JP")
    private var sessionConfigured = false

    private var player: AVAudioPlayer?
    private var playQueue: [Data] = []
    private var fallbackText = ""
    private var fallbackRate = 0.45
    private var workTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?

    private override init() {
        super.init()
        #if DEBUG
        if voice == nil {
            print("[JianRiJi] 系统里没有 ja-JP 语音，去 设置 → 辅助功能 → 朗读内容 → 声音 里下一个。")
        }
        #endif
    }

    var hasJapaneseVoice: Bool { voice != nil }

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

    func speak(_ text: String, rate: Double = 0.45) {
        activateSession()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        fallbackText = trimmed
        fallbackRate = rate

        let base = serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else {
            speakWithSystemVoice(trimmed, rate: rate)
            return
        }

        let percent = ServerTTS.ratePercent(forSpeechRate: rate)
        let chunks = ServerTTS.chunks(of: trimmed)
        guard !chunks.isEmpty else { return }

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
    }

    func stop() {
        workTask?.cancel()
        workTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        playQueue.removeAll()
        player?.stop()
        player = nil
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
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = clampedRate(rate)
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0
        Self.recordEngine("system")
        synthesizer.speak(utterance)
    }

    private func clampedRate(_ rate: Double) -> Float {
        let bounds = Double(AVSpeechUtteranceMinimumSpeechRate)...Double(AVSpeechUtteranceMaximumSpeechRate)
        let safe = min(max(rate, bounds.lowerBound), bounds.upperBound)
        return Float(safe)
    }
}

extension Speech: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.watchdogTask?.cancel()
            self.player = nil
            self.playNext()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.watchdogTask?.cancel()
            self.player = nil
            self.playQueue.removeAll()
            // 已播过的段不再重念，直接停。
        }
    }
}
