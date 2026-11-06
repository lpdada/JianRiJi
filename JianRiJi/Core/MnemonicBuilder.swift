import Foundation

/// 记忆技巧里的一行。
struct MnemonicLine: Identifiable, Hashable {
    let id: String
    /// 左侧的小标签：读音 / 词性 / 构词 / 活用 / 同音 / AI
    let label: String
    let text: String
}

struct Mnemonic {
    let lines: [MnemonicLine]
    var isEmpty: Bool { lines.isEmpty }
}

/// 生成「记忆技巧」。
///
/// 分两层，和这个工程的定位一致（默认不联网）：
///
/// 1. **本地层**立刻出结果，只用词库里已有的事实：拍数、词性用法、构词拆解、活用表、同音词。
///    拿不到就整行不显示，不写"联想小故事"这类编造内容。
/// 2. **AI 层**要用户自己点「AI 深化」才发请求（走已有的 AIClient），结果按词条 id 缓存在本机，
///    下次进同一个词直接读缓存，不会偷偷联网。
enum MnemonicBuilder {

    /// 本地即时生成，最多 4 行。
    static func local(for word: Word) -> Mnemonic {
        var lines: [MnemonicLine] = []
        if let line = readingLine(of: word) { lines.append(line) }
        if let line = partOfSpeechLine(of: word) { lines.append(line) }
        if let line = compositionLine(of: word) { lines.append(line) }
        if let line = conjugationLine(of: word) { lines.append(line) }
        if let line = homophoneLine(of: word) { lines.append(line) }

        // 构词和同音偶尔会撞同一句，去个重。
        var seen = Set<String>()
        let unique = lines.filter { seen.insert($0.text).inserted }
        return Mnemonic(lines: Array(unique.prefix(4)))
    }

    // MARK: - 读音（拍数）

    /// 把假名切成拍：きょうか → [きょ, う, か]。
    /// 小写的 ゃゅょ 等跟着前一个假名算一拍，っ / ー / ん 各算一拍。
    static func morae(_ kana: String) -> [String] {
        let smallKana: Set<Character> = [
            "ゃ", "ゅ", "ょ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ",
            "ャ", "ュ", "ョ", "ァ", "ィ", "ゥ", "ェ", "ォ",
        ]
        var result: [String] = []
        for char in kana {
            if smallKana.contains(char), !result.isEmpty {
                result[result.count - 1].append(char)
            } else {
                result.append(String(char))
            }
        }
        return result
    }

    private static func readingLine(of word: Word) -> MnemonicLine? {
        guard !word.reading.isEmpty else { return nil }
        let beats = morae(word.reading)
        guard !beats.isEmpty else { return nil }
        let romaji = word.romaji.isEmpty ? KanaRomaji.romaji(for: word.reading) : word.romaji
        let text = "\(word.reading)（\(romaji)）共 \(beats.count) 拍，按拍念：\(beats.joined(separator: "・"))"
        return MnemonicLine(id: "reading", label: "读音", text: text)
    }

    // MARK: - 词性用法

    private static func partOfSpeechLine(of word: Word) -> MnemonicLine? {
        let pos = word.partOfSpeech.trimmingCharacters(in: .whitespaces)
        guard !pos.isEmpty else { return nil }

        let hint: String
        if pos.contains("形容动词") || pos.contains("ナ形") {
            hint = "修饰名词加「な」，否定用「〜ではない」。"
        } else if pos.contains("形容词") || pos.contains("イ形") {
            hint = "否定「〜くない」，过去「〜かった」，修饰名词直接接。"
        } else if pos.contains("五段") {
            hint = "五段动词：词尾在 あ／い／う／え／お 五段上变，ます形见下方活用。"
        } else if pos.contains("一段") {
            hint = "一段动词：去掉词尾「る」，再接 ます／て／た。"
        } else if pos.contains("サ变") {
            hint = "サ变动词：「〜する」，ます形「〜します」。"
        } else if pos.contains("カ变") {
            hint = "カ变动词：来る／くる，ます形 来ます／きます。"
        } else if pos.contains("副词") {
            hint = "副词：直接修饰动词或形容词，后面不加助词。"
        } else if pos.contains("接续词") {
            hint = "接续词：放在句首，连接前后两句。"
        } else if pos.contains("代词") {
            hint = "代词：代替名词，直接当主语或宾语。"
        } else if pos.contains("接头词") || pos.contains("接尾词") {
            hint = "构词成分：不能单独用，要粘在别的词前后。"
        } else if pos.contains("名词") {
            hint = "名词：接「の」修饰名词，接「が／を」作主语或宾语。"
        } else {
            hint = ""
        }

        let text = hint.isEmpty ? pos : "\(pos)。\(hint)"
        return MnemonicLine(id: "pos", label: "词性", text: text)
    }

    // MARK: - 构词拆解

    /// 把词形拆成两段词典里都有的词：強化 → 強 + 化（都命中才给，命中一半宁可不说）。
    private static func compositionLine(of word: Word) -> MnemonicLine? {
        let term = word.term
        let chars = Array(term)
        guard chars.count >= 2, chars.count <= 4 else { return nil }
        guard chars.allSatisfy({ isKanji($0) }) else { return nil }

        let segmenter = JapaneseSegmenter.shared
        for split in 1..<chars.count {
            let head = String(chars[0..<split])
            let tail = String(chars[split...])
            guard head != term, tail != term else { continue }
            guard let headWord = segmenter.word(forTerm: head),
                  let tailWord = segmenter.word(forTerm: tail) else { continue }

            let text = "由「\(head)」（\(headWord.reading)：\(clip(headWord.meaning))）"
                + "＋「\(tail)」（\(tailWord.reading)：\(clip(tailWord.meaning))）组成，"
                + "合起来是「\(term)」：\(clip(word.meaning, limit: 16))"
            return MnemonicLine(id: "composition", label: "构词", text: text)
        }
        return nil
    }

    // MARK: - 活用

    private static func conjugationLine(of word: Word) -> MnemonicLine? {
        guard let forms = Conjugation.conjugate(word) else { return nil }
        let rows = forms.displayRows.filter { !$0.value.isEmpty }
        guard !rows.isEmpty else { return nil }
        let text = rows.prefix(4).map { "\($0.label) \($0.value)" }.joined(separator: " ／ ")
        return MnemonicLine(id: "conjugation", label: "活用", text: text)
    }

    // MARK: - 同音

    private static func homophoneLine(of word: Word) -> MnemonicLine? {
        guard !word.reading.isEmpty,
              let other = JapaneseSegmenter.shared.word(forReading: word.reading),
              other.term != word.term else { return nil }
        let text = "和「\(other.term)」（\(clip(other.meaning))）同音，都读 \(word.reading)，只能靠汉字区分。"
        return MnemonicLine(id: "homophone", label: "同音", text: text)
    }

    // MARK: - 小工具

    private static func isKanji(_ char: Character) -> Bool {
        if char == "々" || char == "〆" { return true }
        guard char.unicodeScalars.count == 1, let scalar = char.unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value)
    }

    private static func clip(_ text: String, limit: Int = 12) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }
}

// MARK: - AI 深化

/// AI 记忆技巧的本地缓存 + 请求拼装。只在用户点「AI 深化」时才会真的发请求。
enum MnemonicAI {

    private static func cacheKey(for word: Word) -> String {
        "classic.mnemonic.ai.\(word.id)"
    }

    static func cached(for word: Word) -> [MnemonicLine] {
        guard let raw = UserDefaults.standard.string(forKey: cacheKey(for: word)),
              !raw.isEmpty else { return [] }
        return raw
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .enumerated()
            .map { MnemonicLine(id: "ai-\($0.offset)", label: "AI", text: $0.element) }
    }

    static func store(_ lines: [MnemonicLine], for word: Word) {
        guard !lines.isEmpty else { return }
        let raw = lines.map(\.text).joined(separator: "\n")
        UserDefaults.standard.set(raw, forKey: cacheKey(for: word))
    }

    static func clear(for word: Word) {
        UserDefaults.standard.removeObject(forKey: cacheKey(for: word))
    }

    static func prompt(for word: Word) -> (system: String, user: String) {
        let system = """
        你是日语词条助记编辑，服务对象是中文母语的日语学习者。
        只输出 3 行，每行一句中文，不要编号、不要 Markdown、不要前后缀、不要寒暄。
        第 1 行：拆词形，说明每一块（汉字或词根）是什么意思；拆不出就说明整体构成，不许编造词源。
        第 2 行：给一个具体好记的画面或场景联想。
        第 3 行：指出最容易混的一处（同音词、近义词或助词搭配）。
        """
        var user = """
        词条：\(word.term)
        读音：\(word.reading)（\(word.romaji)）
        词性：\(word.partOfSpeech)
        释义：\(word.meaning)
        """
        if let example = word.example, !example.isEmpty {
            user += "\n例句：\(example)"
            if let zh = word.exampleZh, !zh.isEmpty {
                user += "（\(zh)）"
            }
        }
        return (system, user)
    }

    static func parse(_ response: String) -> [MnemonicLine] {
        response
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .enumerated()
            .map { MnemonicLine(id: "ai-\($0.offset)", label: "AI", text: $0.element) }
    }
}
