//  WordStudyPageView.swift
//  词卡学习页（经典模式）
//
//  ⚠️ v0.4.0 的致命问题：`flipped` 只切换底部按钮，**释义 / 例句 / 记忆技巧始终显示**。
//  也就是说「翻面」这个动作没有任何揭示信息的作用——用户从头到尾看着答案自评，
//  「先回忆、再看答案」这个背单词的核心机制完全失效。ReviewView 里的 `revealed`
//  是对的，这个界面反而退回去了。
//
//  这里的修复：
//   1. 正面（未翻面）**只给词形**；读音默认也藏起来，用户主动点「看提示」才出——
//      否则「看汉字回忆读音」这个训练项根本练不到；
//   2. 释义 / 例句 / 记忆技巧全部移到翻面之后；
//   3. 慢速按钮原来传 0.6（比默认 0.45 更快），改成真正降速；
//   4. 加「撤销」：误点「很熟」不再毁掉复习计划；
//   5. 进度条能走到 100%（原来最后一题永远差一格）；
//   6. 翻面后自动滚回顶部，不用手动上推。

import SwiftUI

// MARK: - 主视图

struct WordStudyPageView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var brainwash: BrainwashStore
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [Word] = []
    @State private var index = 0
    @State private var done = false
    /// 是否已翻面。**它决定答案是否可见**，不只是按钮切换。
    @State private var flipped = false
    /// 翻面前主动看过读音（算用掉一次提示）。
    @State private var hintShown = false
    @State private var showList = false
    @State private var showDetail = false
    @State private var showBrainwash = false

    @State private var selectedTokenID: Int?
    @State private var selectedSegment: ExampleSegment?

    @State private var mnemonicVersion = 0
    @State private var aiLoading = false
    @State private var aiError: String?
    @State private var aiTask: Task<Void, Never>?

    /// 洗脑专用循环器（发音胶囊走 Speech.shared，不共用）。
    @StateObject private var washLoop = SpeechLoop()

    private var current: Word? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    /// 读音是否可见。
    private var readingVisible: Bool { flipped || hintShown }

    /// 本轮进度。翻面算半格，最后一题也能推到 100%。
    private var progress: Double {
        guard !queue.isEmpty else { return 0 }
        let answered = Double(index) + (flipped ? 0.5 : 0)
        return min(1, answered / Double(queue.count))
    }

    /// 慢速朗读的速率。默认 0.45 → 0.30。
    /// 注意 `AVSpeechUtterance.rate` 是「越大越快」，原实现的 0.6 是加速不是减速。
    private var slowRate: Double {
        max(0.30, min(store.settings.speechRate, 0.60) - 0.15)
    }

    var body: some View {
        ZStack {
            AppTheme.bgMint.ignoresSafeArea()

            if done || current == nil {
                finishView
            } else if let word = current {
                VStack(spacing: 0) {
                    navBar
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                Color.clear.frame(height: 1).id("study-top")
                                wordHead(word)
                                pillsRow(word)
                                Divider()
                                    .overlay(AppTheme.hairline)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)

                                if flipped {
                                    definitionRows(word)
                                    exampleSection(word)
                                    tipsSection(word)
                                } else {
                                    recallPrompt(word)
                                }

                                Color.clear.frame(height: 110)
                            }
                        }
                        .onChange(of: flipped) { isFlipped in
                            guard isFlipped else { return }
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("study-top", anchor: .top)
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) { bottomBar(word) }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // 分词索引是全量词库的一次性构建。只在真要用例句分段时建，
            // 不再每次进页面都无脑跑一遍。
            if !JapaneseSegmenter.shared.isPrepared, queue.contains(where: { $0.example != nil }) {
                JapaneseSegmenter.shared.prepare(words: store.words)
            }
            if queue.isEmpty { start() }
        }
        .onDisappear {
            washLoop.stopLoop()
            aiTask?.cancel()
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
        hintShown = false
        selectedTokenID = nil
        selectedSegment = nil
        aiError = nil
    }

    // MARK: - 顶部导航

    private var navBar: some View {
        HStack(spacing: 14) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(AppTheme.ink)
            }
            Text("经典模式")
                .font(.system(size: 19, weight: .heavy))
                .foregroundColor(AppTheme.ink)
            ProgressBarForSession(progress: progress)
            Menu {
                Button { showList = true } label: {
                    Label("查看列表", systemImage: "list.bullet")
                }
                Button { start() } label: {
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
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(AppTheme.ink2)
                    .rotationEffect(.degrees(90))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - 词头（正面的全部内容）

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
                    if readingVisible {
                        Button {
                            speak(word, rate: store.settings.speechRate)
                        } label: {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 18))
                                .foregroundColor(AppTheme.ink2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("朗读这个单词")
                    } else {
                        Button {
                            revealReading(word)
                        } label: {
                            Image(systemName: "eye")
                                .font(.system(size: 18))
                                .foregroundColor(AppTheme.ink2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("看读音提示")
                    }

                    Button {
                        store.toggleFavorite(word)
                    } label: {
                        Image(systemName: store.isFavorite(word) ? "star.fill" : "star")
                            .font(.system(size: 18))
                            .foregroundColor(store.isFavorite(word) ? AppTheme.primary : AppTheme.ink2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.isFavorite(word) ? "取消收藏" : "收藏")

                    Button {
                        showDetail = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 18))
                            .foregroundColor(AppTheme.ink2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("词条详情")
                }
            }

            if readingVisible {
                Text("\(word.reading) ・ \(word.romaji)")
                    .font(.system(size: 19))
                    .foregroundColor(AppTheme.ink2)
            } else {
                // 不显示读音，但也要让用户知道「这里应该有个读音」而不是以为界面坏了。
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 12))
                    Text("先自己回忆读音，再翻面核对")
                        .font(.system(size: 14))
                }
                .foregroundColor(AppTheme.ink3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    // MARK: - 胶囊行

    private func pillsRow(_ word: Word) -> some View {
        HStack(spacing: 10) {
            if readingVisible {
                PillButton {
                    speak(word, rate: store.settings.speechRate)
                } label: {
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 13))
                    Text("发音")
                }
                PillButton {
                    speak(word, rate: slowRate)
                } label: {
                    Image(systemName: "speaker.wave.1.fill").font(.system(size: 13))
                    Text("慢速")
                }
            } else {
                PillButton {
                    revealReading(word)
                } label: {
                    Image(systemName: "eye.fill").font(.system(size: 13))
                    Text("看读音提示")
                }
            }

            Spacer(minLength: 0)

            // 撤销：误点「很熟」时把复习计划救回来。
            if store.canUndoGrade {
                Button {
                    undo()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("撤销")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.ink2)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("撤销上一次评分")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    // MARK: - 正面：回忆提示

    private func recallPrompt(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TagPill(text: word.partOfSpeech.isEmpty ? "词性未知" : word.partOfSpeech)

            Text("先在心里说出它的意思和读法，再翻面。")
                .font(.system(size: 16))
                .foregroundColor(AppTheme.ink2)
                .lineSpacing(3)

            if word.partOfSpeech.contains("动词") {
                Text("动词提示：想一下它的ます形。")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.ink3)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 背面：词义

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
            Text(text)
                .font(.system(size: 17.5))
                .foregroundColor(AppTheme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 背面：例句

    private func exampleSection(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionUnderlineTitle("参考例句")
                Spacer()
                if let example = word.example, !example.isEmpty {
                    Button {
                        Speech.shared.speak(
                            example,
                            rate: store.settings.speechRate,
                            audioKey: exampleAudioKey(word)
                        )
                    } label: {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 17))
                            .foregroundColor(AppTheme.ink2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("朗读例句")
                }
            }
            .padding(.horizontal, 20)

            if let example = word.example, !example.isEmpty {
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
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }
            } else {
                Text("这个词条还没有例句。")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.ink3)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }
        }
        .padding(.top, 18)
    }

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

    // MARK: - 背面：记忆技巧

    private func tipsSection(_ word: Word) -> some View {
        let _ = mnemonicVersion

        let local = MnemonicBuilder.local(for: word)
        let ai = MnemonicAI.cached(for: word)

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionUnderlineTitle("记忆技巧")
                Spacer()
                if aiLoading {
                    ProgressView().scaleEffect(0.7)
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

            if local.isEmpty && ai.isEmpty && !aiLoading {
                Text("这个词条暂时凑不出可讲的点：词库里没有它的构词、活用或同音线索。")
                    .font(.system(size: 14))
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
                    .foregroundColor(AppTheme.danger)
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

    // MARK: - 底部

    private func bottomBar(_ word: Word) -> some View {
        HStack {
            Button(action: { showBrainwash = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .bold))
                    Text("洗脑")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundColor(AppTheme.ink)
                .padding(.horizontal, 24)
                .frame(height: 56)
                .background(
                    Capsule()
                        .fill(AppTheme.card)
                        .shadow(color: AppTheme.cardShadow(6, opacity: 0.08, y: 2), radius: 6, x: 0, y: 2)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            if flipped {
                gradeButtons(word)
            } else {
                MainCTAButton(title: "翻面", icon: "arrow.right") {
                    withAnimation(.easeOut(duration: 0.18)) { flipped = true }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(
            Rectangle()
                .fill(AppTheme.bgMint.opacity(0.94))
                .overlay(alignment: .top) { Divider().overlay(AppTheme.hairline) }
                .ignoresSafeArea()
        )
    }

    /// 四档评分。
    /// 顺序沿用「记得 / 模糊 / 忘了 / 很熟」——「记得」在拇指最顺的位置，
    /// 同时提供撤销，误点不至于毁掉一张卡。
    private func gradeButtons(_ word: Word) -> some View {
        HStack(spacing: 8) {
            ForEach([ReviewGrade.good, .hard, .again, .easy]) { grade in
                Button {
                    pick(grade, for: word)
                } label: {
                    Text(grade.title)
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                        .background(tint(grade).opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundColor(tint(grade))
                .accessibilityLabel("\(grade.title)：\(grade.subtitle)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tint(_ grade: ReviewGrade) -> Color {
        switch grade {
        case .again: return AppTheme.danger
        case .hard: return AppTheme.warning
        case .good: return AppTheme.primary
        case .easy: return AppTheme.success
        }
    }

    private func pick(_ grade: ReviewGrade, for word: Word) {
        store.grade(word: word, grade: grade)
        flipped = false
        hintShown = false
        selectedTokenID = nil
        if index + 1 >= queue.count {
            done = true
        } else {
            index += 1
        }
    }

    private func undo() {
        guard store.undoLastGrade() else { return }
        if index > 0 { index -= 1 }
        flipped = false
        hintShown = false
        selectedTokenID = nil
        selectedSegment = nil
        done = false
    }

    // MARK: - 朗读 / 提示

    private func speak(_ word: Word, rate: Double) {
        Speech.shared.speak(
            word.reading,
            rate: rate,
            audioKey: VoicePack.key(forWord: word.id)
        )
    }

    private func revealReading(_ word: Word) {
        hintShown = true
        speak(word, rate: store.settings.speechRate)
    }

    // MARK: - AI

    private func requestAI(for word: Word) {
        guard !aiLoading else { return }
        aiError = nil
        aiLoading = true
        let prompt = MnemonicAI.prompt(for: word)

        aiTask?.cancel()
        aiTask = Task {
            defer { aiLoading = false }
            do {
                let answer = try await AIClient.chat(
                    settings: store.settings,
                    system: prompt.system,
                    user: prompt.user
                )
                guard !Task.isCancelled else { return }
                let lines = MnemonicAI.parse(answer)
                if lines.isEmpty {
                    aiError = "模型没给出能用的内容，换个模型再试。"
                } else {
                    MnemonicAI.store(lines, for: word)
                    mnemonicVersion += 1
                }
            } catch {
                guard !Task.isCancelled else { return }
                if let aiErrorValue = error as? AIError, aiErrorValue.isSilent { return }
                aiError = error.localizedDescription
            }
        }
    }

    // MARK: - 结算

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

/// 带绿色粗下划线的 Section 标题。
/// 下划线宽度跟随文字——原来写死 96pt，「N5语法」这种短标题会拖一截出去。
struct SectionUnderlineTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 17.5, weight: .heavy))
            .foregroundColor(AppTheme.ink)
            .padding(.bottom, 6)
            .background(alignment: .bottomLeading) {
                Rectangle()
                    .fill(AppTheme.primary)
                    .frame(height: 4)
            }
    }
}

/// 本轮进度条（学习进度胶囊，宽度自适应；进度由调用方传真实值）
struct ProgressBarForSession: View {
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.track)
                Capsule()
                    .fill(AppTheme.primary)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 9)
        .frame(maxWidth: .infinity)
    }
}
