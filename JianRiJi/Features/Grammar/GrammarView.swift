import SwiftUI

/// 语法学习：270 个分级语法点，按级别筛选、可搜句型 / 意义 / 接续 / 备注 / 例句读音 / 标签。
/// 点一条进详情：接续、意义、例句（日文 + 假名 + 中文）、备注，全部可朗读，可标记为学会。
struct GrammarView: View {
    @EnvironmentObject private var store: Store

    @State private var query = ""
    @State private var level = "全部"
    @State private var selected: GrammarPoint?

    private let levels = ["全部", "N5", "N4", "N3", "N2", "N1"]

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [GrammarPoint] {
        store.grammarSearch(trimmedQuery, level: level)
    }

    private var learnedCount: Int { store.learnedGrammarCount(forLevel: level) }
    private var totalCount: Int { store.grammarPoints(forLevel: level).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                searchBar

                Picker("级别", selection: $level) {
                    ForEach(levels, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Text("已学 \(learnedCount) / 共 \(totalCount) 个")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)

                if results.isEmpty {
                    EmptyHint(
                        icon: "book",
                        title: "没找到这个语法点",
                        detail: "换个级别或换个关键词试试，比如「逆接」「条件」。"
                    )
                    .padding(.top, 24)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results) { point in
                            row(point)
                            Rectangle()
                                .fill(Theme.hairline.opacity(0.45))
                                .frame(height: 0.6)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("语法学习")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { point in
            GrammarDetailView(point: point)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)

            TextField("搜语法点、意义或标签", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }

    private func row(_ point: GrammarPoint) -> some View {
        Button {
            selected = point
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(point.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if store.isGrammarLearned(point) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.jade)
                    }
                    Pill(text: point.level, tint: Theme.accent)
                }
                if let meaning = point.meaning {
                    Text(meaning)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                if let tag = point.tag {
                    Text(tag)
                        .font(.caption2)
                        .foregroundStyle(Theme.indigo)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// 语法点详情（「语法豆」点击上滑弹出）—— N5语法 释义/接续/解释 + 分段语法例句
// 对应设计稿: study-and-brainwash.png ③
//
// 数据源 grammar_points.json（字段确认无误）：
//   id / level "N5" / title "〜は〜ではありません" / connection
//   meaning / example / exampleReading / exampleZh / note / tag "判断句"
//
// 说明：
//  · 释义/接续/解释/分类行：字段为空就整行隐藏，不留空行；
//  · 笔记行（添加笔记/笔记专区/编辑解释）—— 主线无笔记后端，去掉；
//  · 添加例句 —— 无添加后端，去掉；
//  · AI 猫爪：AIExplanationView 只接受 Word，语法点没有 Word，
//    这里直接调 AIClient.chat 问语法点（title+meaning 作上下文）；
//  · 麦克风「长按跟读」：不许录音（无麦克风权限），长按 0.4 秒改为播放例句音频，
//    只听不录；用户自己跟读出声。

struct GrammarCardData {
    let level: String          // "N5"
    let title: String          // 〜は〜ではありません
    let meaning: String        // 〜不是〜
    let connection: String     // 名词1は + 名词2では + ありません
    let note: String           // 口语说明（解释区大段文字）
    let example: String        // 私は学生です。
    let exampleReading: String // わたしはがくせいです
    let exampleZh: String      // 我是学生。
    let noteTag: String        // tag「判断句」
}

struct GrammarDetailView: View {
    @EnvironmentObject private var store: Store

    let point: GrammarPoint

    @State private var selectedTokenID: Int?
    @State private var selectedSegment: ExampleSegment?
    @State private var showAI = false
    @State private var aiText: String?
    @State private var aiError: String?
    @State private var aiLoading = false

    private var learned: Bool { store.isGrammarLearned(point) }

    private var grammar: GrammarCardData {
        GrammarCardData(
            level: point.level,
            title: point.title,
            meaning: point.meaning ?? "",
            connection: point.connection ?? "",
            note: point.note ?? "",
            example: point.example ?? "",
            exampleReading: point.exampleReading ?? "",
            exampleZh: point.exampleZh ?? "",
            noteTag: point.tag ?? ""
        )
    }

    /// 语法例句分段（无注音时走助词兜底切分）。
    private var segments: [ExampleToken] {
        guard let example = point.example, !example.isEmpty else { return [] }
        return ExampleTokenizer.tokens(sentence: example, reading: point.exampleReading)
    }

    private func speak(_ text: String, rate: Double? = nil) {
        Speech.shared.speak(text, rate: rate ?? store.settings.speechRate)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                grabber
                titleRow
                pillsRow
                grammarSection
                exampleSection
                if let examples = point.examples, !examples.isEmpty {
                    extraExamplesSection(examples)
                }
                learnButton
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                Color.clear.frame(height: 130)
            }
        }
        .background(Color(hex: 0xEEF4F0))
        .cornerRadius(24, corners: [.topLeft, .topRight])
        // 右下角浮动：AI 猫爪 + 长按跟读
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 10) {
                Button(action: openAI) {
                    ZStack {
                        Circle().fill(AppTheme.primaryDeep)
                            .frame(width: 80, height: 80)
                            .shadow(color: AppTheme.primary.opacity(0.35), radius: 20, x: 0, y: 8)
                        Image(systemName: "pawprint.fill").font(.system(size: 30, weight: .bold)).foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                ZStack {
                    Circle().fill(Color(hex: 0xCFE4D9)).frame(width: 74, height: 74)
                        .shadow(color: AppTheme.primary.opacity(0.2), radius: 16, x: 0, y: 6)
                    Image(systemName: "mic.fill").font(.system(size: 26, weight: .semibold)).foregroundColor(AppTheme.primary)
                }
                // 长按 0.4 秒播放例句音频（只听不录）；原稿的 .infinity 永远触发不了。
                .onLongPressGesture(minimumDuration: 0.4) {
                    if let example = point.example, !example.isEmpty {
                        speak(example)
                    }
                }
                Text("长按跟读").font(.system(size: 12.5, weight: .semibold)).foregroundColor(AppTheme.ink2)
            }
            .padding(.trailing, 16)
            .padding(.bottom, 12)
        }
        .sheet(item: $selectedSegment) { segment in
            ExampleSegmentDetailView(
                segment: segment,
                sentence: point.example ?? "",
                sentenceZh: point.exampleZh
            )
            .environmentObject(store)
        }
        .sheet(isPresented: $showAI) {
            aiSheet
        }
    }

    private var grabber: some View {
        RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xB9C6BF))
            .frame(width: 56, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
    }

    private var titleRow: some View {
        HStack(alignment: .top) {
            Text(grammar.title)
                .font(.system(size: 27, weight: .heavy))
                .foregroundColor(AppTheme.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Spacer()
            HStack(spacing: 6) {
                Pill(text: grammar.level, tint: AppTheme.primary)
                if !grammar.noteTag.isEmpty {
                    Pill(text: grammar.noteTag, tint: AppTheme.indigo)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var pillsRow: some View {
        HStack(spacing: 10) {
            PillButton { speak(grammar.title) } label: {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 13)); Text("发音")
            }
            PillButton { speak(grammar.title, rate: 0.6) } label: {
                Image(systemName: "speaker.wave.1.fill").font(.system(size: 13)); Text("慢速")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var grammarSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionUnderlineTitle("\(grammar.level)语法")
                .padding(.horizontal, 20)
                .padding(.top, 14)

            VStack(alignment: .leading, spacing: 14) {
                if !grammar.meaning.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        TagPill(text: "释义")
                        Text(grammar.meaning).font(.system(size: 17.5)).foregroundColor(AppTheme.ink).lineSpacing(3)
                    }
                }
                if !grammar.connection.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        TagPill(text: "接续")
                        Text(grammar.connection).font(.system(size: 17.5)).foregroundColor(AppTheme.ink).lineSpacing(3)
                    }
                }
                if !grammar.note.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        TagPill(text: "解释")
                        Text(grammar.note).font(.system(size: 16)).foregroundColor(AppTheme.ink).lineSpacing(4)
                    }
                }
                if !grammar.noteTag.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        TagPill(text: "分类")
                        Text(grammar.noteTag).font(.system(size: 16)).foregroundColor(AppTheme.ink2)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private var exampleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionUnderlineTitle("语法例句")
                Spacer()
                if let example = point.example, !example.isEmpty {
                    Button {
                        speak(example)
                    } label: {
                        Image(systemName: "speaker.wave.2").font(.system(size: 17)).foregroundColor(AppTheme.ink2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            if !segments.isEmpty {
                SegmentedExampleView(
                    segments: segments,
                    selectedID: selectedTokenID,
                    onTapSegment: { token in
                        selectedTokenID = token.id
                        selectedSegment = token.toDetailSegment()
                    }
                )
                .padding(.horizontal, 20)
                .padding(.top, 16)

                if !grammar.exampleZh.isEmpty {
                    HStack(alignment: .center, spacing: 12) {
                        LevelBadge(text: grammar.level)
                        Text(grammar.exampleZh)
                            .font(.system(size: 17.5)).foregroundColor(AppTheme.ink).lineSpacing(3)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            } else {
                Text("这个语法点还没有例句。")
                    .font(.footnote)
                    .foregroundColor(AppTheme.ink3)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }
        }
    }

    /// point.examples 里的补充例句：同样分段可点。
    private func extraExamplesSection(_ examples: [GrammarExample]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(examples.enumerated()), id: \.offset) { _, example in
                VStack(alignment: .leading, spacing: 0) {
                    SegmentedExampleView(
                        segments: ExampleTokenizer.tokens(sentence: example.ja),
                        selectedID: selectedTokenID,
                        onTapSegment: { token in
                            selectedTokenID = token.id
                            selectedSegment = token.toDetailSegment()
                        }
                    )
                    HStack(spacing: 12) {
                        Text(example.zh)
                            .font(.subheadline)
                            .foregroundColor(AppTheme.ink2)
                        Spacer()
                        Button {
                            speak(example.ja)
                        } label: {
                            Label("朗读", systemImage: "speaker.wave.2.fill")
                                .font(.caption)
                                .foregroundColor(AppTheme.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 10)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var learnButton: some View {
        Button {
            store.markGrammarLearned(point)
        } label: {
            Text(learned ? "已标记为学会" : "标记为学会")
        }
        .buttonStyle(PrimaryButtonStyle(fill: learned ? Theme.jade : Theme.accent))
    }

    // MARK: - AI 讲解（语法点没有 Word，直接问模型）

    private func openAI() {
        showAI = true
        if aiText == nil, !aiLoading {
            requestAI()
        }
    }

    private func requestAI() {
        guard !aiLoading else { return }
        aiLoading = true
        aiError = nil
        let system = """
        你是日语语法讲解编辑，服务对象是中文母语的日语学习者。
        只输出中文讲解，不要编号、不要 Markdown、不要寒暄。
        分三段：1）这个句型到底是什么意思，什么时候用；2）接续与使用要点；
        3）最容易错的一处（近义句型或助词）。每段 2-3 句。
        """
        var user = "语法点：\(point.title)\n级别：\(point.level)"
        if let meaning = point.meaning, !meaning.isEmpty { user += "\n释义：\(meaning)" }
        if let connection = point.connection, !connection.isEmpty { user += "\n接续：\(connection)" }
        if let example = point.example, !example.isEmpty { user += "\n例句：\(example)" }
        Task {
            do {
                let answer = try await AIClient.chat(settings: store.settings, system: system, user: user)
                aiText = answer
            } catch {
                aiError = error.localizedDescription
            }
            aiLoading = false
        }
    }

    private var aiSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(point.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.primary)
                    if aiLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在问模型……")
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }
                    } else if let aiText {
                        Text(aiText)
                            .font(.system(size: 16))
                            .lineSpacing(4)
                    } else if let aiError {
                        Text(aiError)
                            .font(.subheadline)
                            .foregroundStyle(Color(red: 0.78, green: 0.32, blue: 0.28))
                        Button("再试一次") { requestAI() }
                            .buttonStyle(GhostButtonStyle(tint: AppTheme.primary))
                    }
                    Text("内容是模型生成的，仅供参考，以语法书为准。")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("AI 讲解")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // 只关 AI 讲解这一层，不关外面的语法详情。
                    Button("关闭") { showAI = false }
                }
            }
        }
    }
}

// MARK: - 圆角 helper（sheet 上圆角）

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect,
                          byRoundingCorners: corners,
                          cornerRadii: CGSize(width: radius, height: radius),
                          in: nil).cgPath)
    }
}
