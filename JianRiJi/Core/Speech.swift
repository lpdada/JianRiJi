import AVFoundation

/// 用系统 TTS 念日文。免费、离线、不用联网，也不用申请任何权限。
/// 注意：设备上没装日语语音包时，系统会退回默认语言，听感会差一截。
final class Speech {
    static let shared = Speech()

    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "ja-JP")

    private init() {
        #if DEBUG
        if voice == nil {
            print("[JianRiJi] 系统里没有 ja-JP 语音，去 设置 → 辅助功能 → 朗读内容 → 声音 里下一个。")
        }
        #endif
    }

    var hasJapaneseVoice: Bool { voice != nil }

    func speak(_ text: String, rate: Double = 0.45) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.rate = clampedRate(rate)
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func clampedRate(_ rate: Double) -> Float {
        let bounds = Double(AVSpeechUtteranceMinimumSpeechRate)...Double(AVSpeechUtteranceMaximumSpeechRate)
        let safe = min(max(rate, bounds.lowerBound), bounds.upperBound)
        return Float(safe)
    }
}
