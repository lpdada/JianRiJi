//  SegmentedExample.swift
//  参考例句 · 逐词分段组件（假名上注音 / 罗马字下注 / 每段可点）
//  对应设计稿: study-and-brainwash.png ②③
//
//  数据源已确认（seed_words.json 字段）：
//    example            "日本一"
//    example_furigana   "日本[にほん] 一[いち]"   ← 方括号式注音
//    example_zh         "日本第一"
//  grammar_points.json:
//    example "私は学生です。" / exampleReading "わたしはがくせいです。"
//
//  注意：分段显示模型叫 ExampleToken（不是 ExampleSegment）。
//  主线 JapaneseSegmenter.swift 里已有 ExampleSegment（词库分词结果，带 word/kind），
//  这里的 Token 只管显示；点开详情时用 toDetailSegment() 转成旧段再进
//  ExampleSegmentDetailView。

import SwiftUI

// MARK: - 分段模型

struct ExampleToken: Identifiable, Hashable {
    let id: Int
    let surface: String     // 原文（含标点）
    let furigana: String?   // 上方假名注音（无则为 nil，标点固定无）
    let romaji: String?     // 下方罗马字
    let isPunctuation: Bool
    var isBlank: Bool { surface.trimmingCharacters(in: .whitespaces).isEmpty }

    /// 词库分词器的段转显示段：读音 / 罗马字直接沿用。
    /// 静态工厂（不用 init(old:)：自定义 init 会吃掉 memberwise init 合成）。
    static func fromOld(_ segment: ExampleSegment) -> ExampleToken {
        ExampleToken(
            id: segment.id,
            surface: segment.surface,
            furigana: segment.reading,
            romaji: segment.romaji,
            isPunctuation: segment.kind == .punctuation
        )
    }
}

extension ExampleToken {
    /// 点开详情：先用词库分词器对 surface 查词；整段恰好切成一段时直接用它
    /// （词条 / 活用 / 读音都对得上，读音缺失时补本段的注音）；多段或查不到时
    /// 按本段的注音构造一个无词条段，详情页如实显示词形与读音，不编造释义。
    func toDetailSegment() -> ExampleSegment {
        let segments = JapaneseSegmenter.shared.segment(surface)
        if segments.count == 1 {
            var segment = segments[0]
            if segment.reading == nil, let furigana {
                segment = ExampleSegment(
                    id: segment.id,
                    surface: segment.surface,
                    reading: furigana,
                    word: segment.word,
                    kind: segment.kind
                )
            }
            return segment
        }
        let reading = furigana ?? (ParticleSplitter.isKana(surface) ? surface : nil)
        return ExampleSegment(
            id: id,
            surface: surface,
            reading: reading,
            word: nil,
            kind: isPunctuation ? .punctuation : .other
        )
    }
}

// MARK: - 注音解读（seed_words 方括号格式）

enum BracketFuriganaParser {
    /// "日本[にほん] 一[いち]" -> [("日本","にほん"), ("一","いち")]
    /// 以空白分段；每段内 "词形[读音]" 后面还可能跟 plain（如 "私[わたし]の"
    /// -> ("私","わたし"), ("の",nil)）。
    static func parse(_ marked: String) -> [(surface: String, furigana: String?)] {
        var out: [(String, String?)] = []
        let pieces = marked.split(whereSeparator: { $0.isWhitespace })
        for piece in pieces {
            var rest = String(piece)
            while !rest.isEmpty {
                guard let open = rest.firstIndex(of: "[") else {
                    out.append((rest, nil))
                    break
                }
                let surface = String(rest[..<open])
                guard let close = rest[open...].firstIndex(of: "]") else {
                    // 没有闭合括号：当作普通文字，不丢内容。
                    out.append((rest, nil))
                    break
                }
                let reading = String(rest[rest.index(after: open)..<close])
                if surface.isEmpty {
                    // 括号前没有词形（如 "[わたし]"）：整段按原文保留，不挂读音。
                    out.append((String(rest[...close]), nil))
                } else {
                    out.append((surface, reading.isEmpty ? nil : reading))
                }
                rest = String(rest[rest.index(after: close)...])
            }
        }
        return out
    }

    static func hasBrackets(_ marked: String) -> Bool {
        marked.contains("[") && marked.contains("]")
    }

    /// 去掉方括号后的纯文本（"日本[にほん] 一[いち]" -> "日本一"）。
    static func plainText(_ marked: String) -> String {
        parse(marked).map(\.surface).joined()
    }

    /// 注音的纯文本（忽略空白）是不是就是这句例句本身。
    /// 对不上时（整句假名读音如 "きょうはげつようびです。"、或个别标点间距差异）
    /// 不能硬套注音，调用方应走兜底切分。
    static func plainMatches(_ marked: String, sentence: String) -> Bool {
        let plain = plainText(marked).filter { !$0.isWhitespace }
        let target = sentence.filter { !$0.isWhitespace }
        return !plain.isEmpty && plain == target
    }
}

// MARK: - 语法例句兜底切分（仅助词级）

enum ParticleSplitter {
    /// 从长到短排序，避免"から"被"か"截断
    static let particles = [
        "ありませんでした", "ありません", "ではない", "ではなく", "ましょうかな",
        "でした", "ました", "ません", "ながら", "けど", "から", "まで", "より", "ので", "なのか",
        "です", "する", "した", "して", "である", "では", "でも", "にも", "には", "とは", "のは", "への",
        "は", "が", "を", "に", "で", "へ", "と", "も", "や", "の", "だ", "な", "ょ"
    ]
    /// 按助词切分成 (surface, furigana?)，furigana 仅纯假名段自己即原文。
    /// 空白不进段（句子里的空格只是分隔符）。
    static func split(_ sentence: String) -> [(surface: String, furigana: String?)] {
        var tokens: [(String, String?)] = []
        let rest = Array(sentence)
        var buffer = ""
        let parts = particles.sorted { $0.count > $1.count }
        var idx = 0
        while idx < rest.count {
            let ch = rest[idx]
            if ch == " " || ch == "\u{3000}" || ch == "\n" || ch == "\t" {
                if !buffer.isEmpty { tokens.append((buffer, nil)); buffer = "" }
                idx += 1
                continue
            }
            var matched = false
            for p in parts {
                let chars = Array(p)
                if idx + chars.count <= rest.count, Array(rest[idx..<(idx + chars.count)]) == chars {
                    if !buffer.isEmpty { tokens.append((buffer, nil)); buffer = "" }
                    tokens.append((p, isKana(p) ? p : nil))
                    idx += chars.count
                    matched = true
                    break
                }
            }
            if !matched {
                buffer.append(rest[idx]); idx += 1
            }
        }
        if !buffer.isEmpty { tokens.append((buffer, nil)) }
        return tokens
    }
    static func isKana(_ s: String) -> Bool {
        s.unicodeScalars.allSatisfy {
            ($0.value >= 0x3041 && $0.value <= 0x3096) || ($0.value >= 0x30A1 && $0.value <= 0x30FA)
        }
    }
}

// MARK: - 罗马字转换（Hepburn）

enum Romaji {
    static let table: [String: String] = {
        var t: [String: String] = [:]
        let base: [(String, String)] = [
            ("あ","a"),("い","i"),("う","u"),("え","e"),("お","o"),
            ("か","ka"),("き","ki"),("く","ku"),("け","ke"),("こ","ko"),
            ("さ","sa"),("し","shi"),("す","su"),("せ","se"),("そ","so"),
            ("た","ta"),("ち","chi"),("つ","tsu"),("て","te"),("と","to"),
            ("な","na"),("に","ni"),("ぬ","nu"),("ね","ne"),("の","no"),
            ("は","ha"),("ひ","hi"),("ふ","fu"),("へ","he"),("ほ","ho"),
            ("ま","ma"),("み","mi"),("む","mu"),("め","me"),("も","mo"),
            ("や","ya"),("ゆ","yu"),("よ","yo"),
            ("ら","ra"),("り","ri"),("る","ru"),("れ","re"),("ろ","ro"),
            ("わ","wa"),("を","o"),("ん","n"),
            ("が","ga"),("ぎ","gi"),("ぐ","gu"),("げ","ge"),("ご","go"),
            ("ざ","za"),("じ","ji"),("ず","zu"),("ぜ","ze"),("ぞ","zo"),
            ("だ","da"),("ぢ","ji"),("づ","zu"),("で","de"),("ど","do"),
            ("ば","ba"),("び","bi"),("ぶ","bu"),("べ","be"),("ぼ","bo"),
            ("ぱ","pa"),("ぴ","pi"),("ぷ","pu"),("ぺ","pe"),("ぽ","po"),
        ]
        for (k, v) in base { t[k] = v }
        let youon: [(String, String)] = [
            ("きゃ","kya"),("きゅ","kyu"),("きょ","kyo"),
            ("しゃ","sha"),("しゅ","shu"),("しょ","sho"),
            ("ちゃ","cha"),("ちゅ","chu"),("ちょ","cho"),
            ("にゃ","nya"),("にゅ","nyu"),("にょ","nyo"),
            ("ひゃ","hya"),("ひゅ","hyu"),("ひょ","hyo"),
            ("みゃ","mya"),("みゅ","myu"),("みょ","myo"),
            ("りゃ","rya"),("りゅ","ryu"),("りょ","ryo"),
            ("ぎゃ","gya"),("ぎゅ","gyu"),("ぎょ","gyo"),
            ("じゃ","ja"),("じゅ","ju"),("じょ","jo"),
            ("びゃ","bya"),("びゅ","byu"),("びょ","byo"),
            ("ぴゃ","pya"),("ぴゅ","pyu"),("ぴょ","pyo"),
        ]
        for (k, v) in youon { t[k] = v }
        return t
    }()

    /// 假名 -> 罗马字；非假名字符原样保留
    static func romaji(from kana: String) -> String {
        var out = ""
        let chars = Array(kana)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "っ" || ch == "ッ" {
                if i + 1 < chars.count { out += sokuonExtra(for: chars[i + 1]) }
                i += 1; continue
            }
            if ch == "ー" || ch == "ｰ" {
                if let last = out.last, last.isVowel { out.append(last) }
                i += 1; continue
            }
            if i + 1 < chars.count, let r = table[String(chars[i...i+1])] {
                out += r; i += 2; continue
            }
            if let r = table[String(ch)] { out += r }
            else if !(ch == "。" || ch == "、" || ch == "　") { out.append(ch) }
            i += 1
        }
        return out
    }

    /// 促音重复下一拍首辅音：っし→s(shi)、っち→t(chi)、っか→k(ka)
    static func sokuonExtra(for nextKana: Character) -> String {
        guard let r = table[String(nextKana)], let first = r.first, !first.isVowel else { return "" }
        return first == "c" ? "t" : String(first)
    }
}

extension Character {
    var isVowel: Bool { "aeiou".contains(self) }
}

// MARK: - Token 生成器

enum ExampleTokenizer {
    /// 词条例句：方括号注音与例句对得上时用注音切分；否则按助词兜底。
    /// reading 是整句假名读音（如语法例句的 exampleReading），当前切分不依赖它
    /// 做逐段对齐（没有逐段对齐数据，不硬套），只保留在签名里备用。
    static func tokens(sentence: String, furigana: String? = nil, reading: String? = nil) -> [ExampleToken] {
        var parsed: [(String, String?)]
        if let f = furigana, !f.isEmpty,
           BracketFuriganaParser.hasBrackets(f),
           BracketFuriganaParser.plainMatches(f, sentence: sentence) {
            parsed = BracketFuriganaParser.parse(f)
        } else {
            parsed = ParticleSplitter.split(sentence)
        }
        var out: [ExampleToken] = []
        var id = 0
        for (surface, fur) in parsed {
            if surface.isEmpty { continue }
            let isPunct = surface.count <= 1 && "。、！？!?,. \u{3000}".contains(surface.first ?? "x")
            let kanaSource = fur ?? (ParticleSplitter.isKana(surface) ? surface : nil)
            let romaji: String? = isPunct ? nil : kanaSource.map { Romaji.romaji(from: $0) }
            out.append(ExampleToken(id: id, surface: surface,
                                    furigana: isPunct ? nil : fur,
                                    romaji: romaji, isPunctuation: isPunct))
            id += 1
        }
        return out
    }
}

// MARK: - 分段例句视图

/// 逐词分段渲染；selected 段高亮 + 点击回调（设计稿「連携」选中效果）
struct SegmentedExampleView: View {
    let segments: [ExampleToken]
    var selectedID: Int? = nil
    var onTapSegment: (ExampleToken) -> Void = { _ in }

    var body: some View {
        SegmentFlowLayout(alignment: .leading, spacing: 6, lineSpacing: 20) {
            ForEach(segments) { seg in
                segmentView(seg)
            }
        }
    }

    @ViewBuilder
    private func segmentView(_ seg: ExampleToken) -> some View {
        if seg.isPunctuation || seg.isBlank {
            Text(seg.surface)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(AppTheme.ink)
        } else {
            let selected = selectedID == seg.id
            VStack(spacing: 3) {
                Text(seg.furigana ?? " ")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(AppTheme.ink3)
                    .lineLimit(1)
                Text(seg.surface)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(selected ? AppTheme.primary : AppTheme.ink)
                    .lineLimit(1)
                Text(seg.romaji ?? " ")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundColor(Color(hex: 0x8F9C95))
                    .lineLimit(1)
            }
            .padding(.horizontal, 3)
            .padding(.bottom, 4)
            .background(selected ? AnyShapeStyle(AppTheme.primarySoft.opacity(0.55)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(selected ? AppTheme.primary : Color(hex: 0xC9D8D1))
                    .frame(height: 2.5)
                    .padding(.horizontal, 1)
            }
            .contentShape(Rectangle())
            .onTapGesture { onTapSegment(seg) }
        }
    }
}

// MARK: - SegmentFlowLayout（自研换行，iOS 16+ Layout 协议）
//
// 主线 Design/FlowLayout.swift 已有一个 FlowLayout（horizontalSpacing /
// verticalSpacing，经典模式在用），这里改名 SegmentFlowLayout，不动旧的。

struct SegmentFlowLayout: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = layout(proposal: proposal, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(0, rows.count - 1)) * lineSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layout(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for (colIdx, viewIdx) in row.indices.enumerated() {
                let size = row.sizes[colIdx]
                subviews[viewIdx].place(at: CGPoint(x: x, y: y + row.height - size.height), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0
        for (idx, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                rows.append(current)
                current = Row()
                x = 0
            }
            current.indices.append(idx)
            current.sizes.append(size)
            current.width = x + size.width
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
