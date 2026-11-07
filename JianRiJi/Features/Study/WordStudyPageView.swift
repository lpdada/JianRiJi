//  WordStudyPageView.swift
//  词卡学习页（经典模式）改版 —— 参考例句逐词分段可点 + 记忆技巧 + 底部 洗脑/翻面
//  对应设计稿: study-and-brainwash.png ①②
//
//  队列与评分沿用 ClassicModeView 同一套：sessionQueue() 喂数据，
//  Store.grade(word:grade:) 记分；洗脑只循环朗读，不推进记忆曲线。
//  SRS 流程：正面翻面记忆 → 背面四档评分（记得/模糊/忘了/很熟）。
//
//  没有后端的功能不留按钮：
//   · 笔记（添加笔记/笔记专区/编辑词义）—— 主线无笔记后端，整行去掉；
//   · 添加例句/语法/更多 —— 无添加例句后端、无词条→语法点的映射，整行去掉；
//   · 用户朗读人数 —— 无真人读音数据，胶囊隐藏；
//   · 日文释义行 —— Word 没有日文释义字段，隐藏（释义行只剩词性+中文，
//     另有 note 时再加一行「解析」；不把同一中文释义印两遍）；
//   · 💡 汇总句 —— MnemonicBuilder 没有单独的汇总 API，隐藏，不编造；
//   · 右下角浮动「长按跟读」mic —— 录音功能不许加，不留。

import SwiftUI

// MARK: - 主视图

struct WordStudyPageView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var brainwash: BrainwashStore
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [Word] = []
    @State private var index = 0
    @State private var done = false
    @State private var flipped = false
    @State private var showList = false
    @State private var showDetail = false
    @State private var showBrainwash = false

    @State private var selectedTokenID: Int?
    @State private var selectedSegment: ExampleSegment?

    @State private var mnemonicVersion = 0
    @State private var aiLoading = false
    @State private var aiError: String?

    /// 洗脑专用循环器（发音胶囊走 Speech.shared，不共用）。
    @StateObject private var washLoop = SpeechLoop()

    private var current: Word? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    private var progress: Double {
        guard !queue.isEmpty else { return 0 }
        return Double(index) / Double(queue.count)
    }

    var body: some View {
        ZStack {
            AppTheme.bgMint.ignoresSafeArea()

            if done || current == nil {
                finishView
            } else if let word = current {
                VStack(spacing: 0) {
                    navBar
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            wordHead(word)
                            pillsRow(word)
                            Divider().overlay(AppTheme.hairline).padding(.horizontal, 20).padding(.vertical, 12)
                            definitionRows(word)
                            exampleSection(word)
                            tipsSection(word)
                            Color.clear.frame(height: 110)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) { bottomBar(word) }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // 分词索引是全量词库的一次性构建，进页面时备好，之后翻词不再重建。
            if !JapaneseSegmenter.shared.isPrepared {
                JapaneseSegmenter.shared.prepare(words: store.words)
            }
            if queue.isEmpty { start() }
        }
        .onDisappear {
            washLoop.stopLoop()
        }
        .sheet(isPresented: $showList) {
            QueueListView(queue: queue, currentIndex: index, title: store.currentBookTitle)
        }
        .sheet(isPresented: $showDetail) {
            if let word = current {
                WordDetailView(word: word)
            }
        }
        .sheet(item: $selectedSegment) { segment in
            ExampleSegmentDetailView(
                segment: segment,
                sentence: current?.example ?? "",
                sentenceZh: current?.exampleZh
            )
            .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showBrainwash) {
            if let word = current {
                BrainwashOverlayView(
                    config: brainwash,
                    loop: washLoop,
                    wordText: word.reading,
                    sentenceText: word.example ?? "",
                    wordAudioKey: VoicePack.key(forWord: word.id),
                    sentenceAudioKey: exampleAudioKey(word)
                ) {
                    showBrainwash = false
                }
            }
        }
    }

    private func start() {
        washLoop.stopLoop()
        queue = store.sessionQueue()
        index = 0
        done = false
        flipped = false
        selectedTokenID = nil
        selectedSegment = nil
        aiError = nil
    }

    // MARK: - 顶部导航

    private var navBar: some View {
        HStack(spacing: 14) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold)).foregroundColor(AppTheme.ink)
            }
            Text("经典模式")
                .font(.system(size: 19, weight: .heavy))
                .foregroundColor(AppTheme.ink)
            ProgressBarForSession(progress: progress)
            Menu {
                Button {
                    showList = true
                } label: {
                    Label("查看列表", systemImage: "list.bullet")
                }
                Button {
                    start()
                } label: {
                    Label("重新开始", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    washLoop.stopLoop()
                    done = true
                } label: {
                    Label("结束本轮", systemImage: "xmark")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold)).foregroundColor(AppTheme.ink2)
                    .rotationEffect(.degrees(90))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - 词头

    private func wordHead(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(word.term)
                    .font(.system(size: 42, weight: .heavy))
                    .foregroundColor(AppTheme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                HStack(spacing: 18) {
                    Button {
                        Speech.shared.speak(
                            word.reading,
                            rate: store.settings.speechRate,
                            audioKey: VoicePack.key(forWord: word.id)
                        )
                    } label: {
                        Image(systemName: "speaker.wave.2").font(.system(size: 18)).foregroundColor(AppTheme.ink2)
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.toggleFavorite(word)
                    } label: {
                        Image(systemName: store.isFavorite(word) ? "star.fill" : "star")
                            .font(.system(size: 18)).foregroundColor(AppTheme.ink2)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showDetail = true
                    } label: {
                        Image(systemName: "info.circle").font(.system(size: 18)).foregroundColor(AppTheme.ink2)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("\(word.reading) ・ \(word.romaji)")
                .font(.system(size: 19))
                .foregroundColor(Color(hex: 0x6C7A74))
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    // MARK: - 发音胶囊行

    private func pillsRow(_ word: Word) -> some View {
        HStack(spacing: 10) {
            PillButton {
                Speech.shared.speak(
                    word.reading,
                    rate: store.settings.speechRate,
                    audioKey: VoicePack.key(forWord: word.id)
                )
            } label: {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 13))
                Text("发音")
            }
            PillButton {
                Speech.shared.speak(
                    word.reading,
                    rate: 0.6,
                    audioKey: VoicePack.key(forWord: word.id)
                )
            } label: {
                Image(systemName: "speaker.wave.1.fill").font(.system(size: 13))
                Text("慢速")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    // MARK: - 词义行（词性 + 中文；有精讲解析时再加一行）

    private func definitionRows(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            defRow(tag: word.partOfSpeech.isEmpty ? "释义" : word.partOfSpeech, text: word.meaning)
            if let note = word.note, !note.isEmpty {
                defRow(tag: "解析", text: note)
            }
        }
        .padding(.horizontal, 20)
    }

    private func defRow(tag: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            TagPill(text: tag)
            Text(text).font(.system(size: 17.5)).foregroundColor(AppTheme.ink).lineSpacing(3)
        }
    }

    // MARK: - 参考例句（分段）

    private func exampleSection(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionUnderlineTitle("参考例句")
                Spacer()
                HStack(spacing: 20) {
                    Button {
                        store.toggleFavorite(word)
                    } label: {
                        Image(systemName: store.isFavorite(word) ? "star.fill" : "star")
                            .font(.system(size: 17)).foregroundColor(AppTheme.ink2)
                    }
                    .buttonStyle(.plain)
                    if let example = word.example, !example.isEmpty {
                        Button {
                            Speech.shared.speak(
                                example,
                                rate: store.settings.speechRate,
                                audioKey: exampleAudioKey(word)
                            )
                        } label: {
                            Image(systemName: "speaker.wave.2").font(.system(size: 17)).foregroundColor(AppTheme.ink2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)

            if let example = word.example, !example.isEmpty {
                // 分段例句（tap → 详情页，已有 ExampleSegmentDetailView）
                SegmentedExampleView(
                    segments: exampleTokens(for: word),
                    selectedID: selectedTokenID,
                    onTapSegment: { token in
                        selectedTokenID = token.id
                        selectedSegment = token.toDetailSegment()
                    }
                )
                .padding(.horizontal, 20)
                .padding(.top, 16)

                if let zh = word.exampleZh, !zh.isEmpty {
                    HStack(alignment: .center, spacing: 12) {
                        LevelBadge(text: word.jlpt)
                        Text(zh)
                            .font(.system(size: 17.5))
                            .foregroundColor(AppTheme.ink)
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }
            } else {
                Text("这个词条还没有例句。")
                    .font(.footnote)
                    .foregroundColor(AppTheme.ink3)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }
        }
        .padding(.top, 18)
    }

    /// 例句分段：方括号注音与例句对得上时用注音切分；对不上时（147 条是整句
    /// 假名读音）用词库分词器兜底，读音来自词典，和旧经典卡一致。
    private func exampleTokens(for word: Word) -> [ExampleToken] {
        guard let example = word.example, !example.isEmpty else { return [] }
        if let furigana = word.exampleFurigana,
           BracketFuriganaParser.hasBrackets(furigana),
           BracketFuriganaParser.plainMatches(furigana, sentence: example) {
            return ExampleTokenizer.tokens(sentence: example, furigana: furigana)
        }
        return JapaneseSegmenter.shared.segment(example).map(ExampleToken.fromOld)
    }

    /// 例句的真人音频 key：`w-<词条id>-ex`，由「生成真人语音」写入。
    private func exampleAudioKey(_ word: Word) -> String {
        VoicePack.key(forWord: word.id) + "-ex"
    }

    // MARK: - 记忆技巧

    private func tipsSection(_ word: Word) -> some View {
        // 依赖一下这个版本号，AI 结果写进缓存后能触发重画。
        let _ = mnemonicVersion

        let local = MnemonicBuilder.local(for: word)
        let ai = MnemonicAI.cached(for: word)

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionUnderlineTitle("记忆技巧")
                Spacer()
                if aiLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button {
                        requestAI(for: word)
                    } label: {
                        Label(ai.isEmpty ? "AI 深化" : "重新生成", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundColor(AppTheme.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            if local.isEmpty && ai.isEmpty {
                Text("这个词条暂时凑不出可讲的点：词库里没有它的构词、活用或同音线索。")
                    .font(.footnote)
                    .foregroundColor(AppTheme.ink3)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            VStack(spacing: 0) {
                ForEach(local.lines) { line in
                    tipRow(line)
                }
                ForEach(ai) { line in
                    tipRow(line)
                }
            }
            .padding(.horizontal, 20)

            if let aiError {
                Text(aiError)
                    .font(.caption2)
                    .foregroundColor(Color(red: 0.78, green: 0.32, blue: 0.28))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
        }
        .padding(.top, 20)
    }

    private func tipRow(_ line: MnemonicLine) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(line.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.primary)
                .frame(width: 30, alignment: .leading)
                .padding(.top, 2)

            Text(line.text)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().overlay(AppTheme.hairline) }
    }

    private func requestAI(for word: Word) {
        guard !aiLoading else { return }
        aiError = nil
        aiLoading = true
        let prompt = MnemonicAI.prompt(for: word)

        Task {
            do {
                let answer = try await AIClient.chat(
                    settings: store.settings,
                    system: prompt.system,
                    user: prompt.user
                )
                let lines = MnemonicAI.parse(answer)
                if lines.isEmpty {
                    aiError = "模型没给出能用的内容，换个模型再试。"
                } else {
                    MnemonicAI.store(lines, for: word)
                    mnemonicVersion += 1
                }
            } catch {
                aiError = error.localizedDescription
            }
            aiLoading = false
        }
    }

    // MARK: - 底部：洗脑 + 翻面 / 四档评分

    private func bottomBar(_ word: Word) -> some View {
        HStack {
            Button(action: { showBrainwash = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 15, weight: .bold))
                    Text("洗脑").font(.system(size: 17, weight: .bold))
                }
                .foregroundColor(AppTheme.ink)
                .padding(.horizontal, 24)
                .frame(height: 56)
                .background(Capsule().fill(AppTheme.card).shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2))
            }
            .buttonStyle(.plain)
            Spacer()
            if flipped {
                gradeButtons(word)
            } else {
                MainCTAButton(title: "翻面", icon: "arrow.right", action: { flipped = true })
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(
            Rectangle().fill(AppTheme.bgMint.opacity(0.94))
                .overlay(alignment: .top) { Divider().overlay(AppTheme.hairline) }
                .ignoresSafeArea()
        )
    }

    /// 翻面后右侧槽位换成四档评分：记得 / 模糊 / 忘了 / 很熟。
    private func gradeButtons(_ word: Word) -> some View {
        HStack(spacing: 8) {
            ForEach([ReviewGrade.good, .hard, .again, .easy]) { grade in
                Button {
                    pick(grade, for: word)
                } label: {
                    Text(grade.title)
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(tint(grade).opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundColor(tint(grade))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tint(_ grade: ReviewGrade) -> Color {
        switch grade {
        case .again: return Color(red: 0.78, green: 0.32, blue: 0.28)
        case .hard: return Color(red: 0.72, green: 0.52, blue: 0.20)
        case .good: return AppTheme.primary
        case .easy: return Color(red: 0.239, green: 0.620, blue: 0.470)
        }
    }

    private func pick(_ grade: ReviewGrade, for word: Word) {
        store.grade(word: word, grade: grade)
        flipped = false
        selectedTokenID = nil
        if index + 1 >= queue.count {
            done = true
        } else {
            index += 1
        }
    }

    private var finishView: some View {
        VStack(spacing: 16) {
            EmptyHint(
                icon: "checkmark.seal",
                title: queue.isEmpty ? "当前词本是空的" : "这一轮走完了",
                detail: queue.isEmpty
                    ? "先在词本里选一个有词的级别。"
                    : "点下方重新开始。"
            )
            Button("重新开始") {
                start()
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .overlay(Capsule().strokeBorder(AppTheme.primary.opacity(0.4), lineWidth: 1))
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - 小组件

/// 带绿色粗下划线的 Section 标题（参考例句 / 记忆技巧 / N5语法 / 语法例句）
struct SectionUnderlineTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 17.5, weight: .heavy))
            .foregroundColor(AppTheme.ink)
            .frame(alignment: .leading)
            .padding(.bottom, 6)
            .background(alignment: .bottomLeading) {
                Rectangle().fill(AppTheme.primary).frame(width: 96, height: 4)
            }
    }
}

/// 本轮进度条（学习进度胶囊，宽度自适应；进度由调用方传真实值）
struct ProgressBarForSession: View {
    var progress: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0xD6E4DD))
                Capsule().fill(Color(hex: 0xBFE0D3)).frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 9)
        .frame(maxWidth: .infinity)
    }
}
