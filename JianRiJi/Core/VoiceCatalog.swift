import AVFoundation
import Foundation

/// 一条可选语音。`identifier` 是系统语音的稳定标识，用来记住用户的选择。
struct VoiceOption: Identifiable, Hashable {
    let id: String
    /// 系统给的名字，如 Kyoko / Otoya / O-ren
    let name: String
    /// 音质档位：3 = 高级（premium）、2 = 增强（enhanced）、1 = 默认（compact）
    let qualityRank: Int

    var qualityLabel: String {
        switch qualityRank {
        case 3: return "高级"
        case 2: return "增强"
        default: return "默认"
        }
    }

    /// 默认档就是「听着机械」的那一档。界面上要据此提示用户去下载更好的语音包。
    var isHighQuality: Bool { qualityRank >= 2 }
}

/// 系统语音清单与选择。
///
/// 为什么声音会"机械化"：iOS 的日语语音分三档，同一台设备上可能同时存在
/// `Kyoko`（compact，几百 KB，机械）和 `Kyoko (Enhanced)`（几十 MB，自然得多）。
/// `AVSpeechSynthesisVoice(language: "ja-JP")` 只会拿到系统给的默认那一档，
/// 基本都是 compact。这里改成：列出全部日语语音，按音质排序，让用户自己挑。
enum VoiceCatalog {

    static let selectedKey = "speech.voiceIdentifier"

    private static func qualityRank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium: return 3
        case .enhanced: return 2
        default: return 1
        }
    }

    /// 设备上所有日语语音，音质高的在前面。
    static func japaneseVoices() -> [VoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ja") }
            .map {
                VoiceOption(
                    id: $0.identifier,
                    name: $0.name,
                    qualityRank: qualityRank($0.quality)
                )
            }
            .sorted { lhs, rhs in
                if lhs.qualityRank != rhs.qualityRank { return lhs.qualityRank > rhs.qualityRank }
                return lhs.name < rhs.name
            }
    }

    /// 设备上最好的日语语音。
    static func best() -> VoiceOption? {
        japaneseVoices().first
    }

    /// 用户选中的那条；选过但现在不可用（卸载了语音包）就回退到最好的。
    static func current() -> VoiceOption? {
        let voices = japaneseVoices()
        if let saved = UserDefaults.standard.string(forKey: selectedKey),
           let hit = voices.first(where: { $0.id == saved }) {
            return hit
        }
        return voices.first
    }

    static func select(_ option: VoiceOption?) {
        if let option {
            UserDefaults.standard.set(option.id, forKey: selectedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedKey)
        }
    }

    /// 真正喂给 AVSpeechUtterance 的语音对象。
    static func utteranceVoice() -> AVSpeechSynthesisVoice? {
        if let option = current(), let voice = AVSpeechSynthesisVoice(identifier: option.id) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: "ja-JP")
    }

    /// 当前是否只是默认（机械）档——界面上要据此给下载引导。
    static var isUsingCompactVoice: Bool {
        guard let option = current() else { return false }
        return !option.isHighQuality
    }

    /// 系统里一个日语语音都没有：连默认档都没装。
    static var hasNoJapaneseVoice: Bool {
        japaneseVoices().isEmpty
    }
}

/// 把长句切成短句，交给 TTS 一段一段念。
///
/// 系统 TTS 一口气念很长一句时会明显发平、像播报；按句读断开、每段之间留一点点间隔，
/// 听感接近正常人说话的换气。切点优先句末标点，其次逗号，太长才硬切。
enum SpeechText {

    private static let sentenceEnd: Set<Character> = ["。", "！", "？", "!", "?", "…"]
    private static let clauseEnd: Set<Character> = ["、", "，", ","]

    static func split(_ text: String, limit: Int = 24) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var pieces: [String] = []
        var current = ""

        for char in trimmed {
            current.append(char)

            if sentenceEnd.contains(char) {
                pieces.append(current)
                current = ""
                continue
            }
            // 逗号不停顿在半句开头，避免切出「、とても」这种碎片。
            if clauseEnd.contains(char), current.count >= 6 {
                pieces.append(current)
                current = ""
                continue
            }
            if current.count >= limit {
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty { pieces.append(current) }

        let cleaned = pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return cleaned.isEmpty ? [trimmed] : cleaned
    }
}
