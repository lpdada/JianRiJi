import SwiftUI

/// 经典模式：大字词卡布局，只用本地数据，不造假社区 / 真人语音 / 用户数。
///
/// 相对 v0.4.0 的改动：
/// - 顶部：发音 / 慢速，多一个「例句自动读」开关；
/// - 中间：词性 + 中文释义（不翻面）；有精讲解析时接在释义下面；
/// - 参考例句：**本地分词**成一段一段，每段上面假名、下面 romaji，
///   点任意一段弹它自己的详情（能对上词条就给完整词条，对不上就如实说没收录）；
/// - 记忆技巧：本地即时生成（拍数 / 词性用法 / 构词 / 活用 / 同音），
///   AI 深化要用户自己点，结果缓存在本机；
/// - 洗脑：循环念「词读音 + 例句」共 10 遍，点一下暂停、再点继续，旁边 ✕ 直接停。
struct ClassicModeView: View {
    @EnvironmentObject private var store: Store

    @State private var queue: [Word] = []
    @State private var index = 0
    @State private var done = false
    @State private var goodCount = 0
    @State private var showList = false
    @State private var showDetail = false

    @State private var selectedSegment: ExampleSegment?
    @State private var mnemonicVersion = 0
    @State private var aiLoading = false
    @State private var aiError: String?

    @StateObject private var speaker = SpeechLoop()

    /// 洗脑读几遍。参考实现是 10 遍上下，这里定死 10。
    private let washRounds = 10

    /// 进词条自动朗读例句的开关。跟着界面走，不动 Store 的 AppSettings。
    @AppStorage("classic.autoSpeakExample") private var autoSpeakExample = true

    private var current: Word? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    private var progress: CGFloat {
        guard !queue.isEmpty else { return 0 }
        return CGFloat(index) / CGFloat(queue.count)
    }

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()

            if done || current == nil {
                finishView
            } else if let word = current {
                VStack(spacing: 0) {
                    progressBar

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            titleBlock(word)
                            actionPills(word)
                            meaningBlock(word)
                            referenceExample(word)
                            mnemonicBlock(word)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 24)
                    }

                    bottomBar(word)
                }
            }
        }
        .navigationTitle("经典模式")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
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
                        speaker.stopLoop()
                        done = true
                    } label: {
                        Label("结束本轮", systemImage: "xmark")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .onAppear {
            // 分词索引是全量词库的一次性构建，进页面时备好，之后翻词不再重建。
            if !JapaneseSegmenter.shared.isPrepared {
                JapaneseSegmenter.shared.prepare(words: store.words)
            }
            if queue.isEmpty { start() }
        }
        .onDisappear {
            speaker.stopLoop()
        }
        .task(id: index) {
            guard !done, autoSpeakExample, let word = current, !speaker.isRunning else { return }
            // 留一点时间让卡片先画出来，别一进页面就抢着念。
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard autoSpeakExample, !speaker.isRunning else { return }
            if let example = word.example, !example.isEmpty {
                speaker.speak(
                    SpeechLine(example, audioKey: exampleAudioKey(word)),
                    rate: store.settings.speechRate
                )
            } else {
                speaker.speak(
                    SpeechLine(word.reading, audioKey: VoicePack.key(forWord: word.id)),
                    rate: store.settings.speechRate
                )
            }
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
    }

    private func start() {
        speaker.stopLoop()
        queue = store.sessionQueue()
        index = 0
        done = false
        goodCount = 0
        selectedSegment = nil
        aiError = nil
    }

    // MARK: - 卡片

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.mint)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(6, geo.size.width * progress))
            }
        }
        .frame(height: 6)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func titleBlock(_ word: Word) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(word.term)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text("\(word.reading)  ・  \(word.romaji)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }

            Spacer(minLength: 8)

            HStack(spacing: 14) {
                Button {
                    Speech.shared.speak(
                        word.reading,
                        rate: store.settings.speechRate,
                        audioKey: VoicePack.key(forWord: word.id)
                    )
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)

                Button {
                    store.toggleFavorite(word)
                } label: {
                    Image(systemName: store.isFavorite(word) ? "star.fill" : "star")
                        .foregroundStyle(store.isFavorite(word) ? Theme.accent : Theme.muted)
                }
                .buttonStyle(.plain)

                Button {
                    showDetail = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 17))
        }
    }

    private func actionPills(_ word: Word) -> some View {
        HStack(spacing: 8) {
            capsule("发音", icon: "speaker.wave.2.fill") {
                Speech.shared.speak(
                    word.reading,
                    rate: store.settings.speechRate,
                    audioKey: VoicePack.key(forWord: word.id)
                )
            }
            capsule("慢速", icon: "tortoise.fill") {
                Speech.shared.speak(
                    word.reading,
                    rate: max(0.30, store.settings.speechRate - 0.15),
                    audioKey: VoicePack.key(forWord: word.id)
                )
            }
            capsule(
                autoSpeakExample ? "自动读" : "静音",
                icon: autoSpeakExample ? "speaker.wave.3.fill" : "speaker.slash.fill"
            ) {
                autoSpeakExample.toggle()
                if !autoSpeakExample { speaker.stopLoop() }
            }
            Spacer(minLength: 0)
        }
    }

    private func capsule(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.footnote)
            }
            .foregroundStyle(Theme.indigo)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.mint.opacity(0.55), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func meaningBlock(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Pill(text: word.partOfSpeech, tint: Theme.indigo)
                Text(word.meaning)
                    .font(.system(size: 20, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if let note = word.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 参考例句

    private func referenceExample(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                sectionTitle("参考例句")
                Spacer()
                Button {
                    autoSpeakExample.toggle()
                    if !autoSpeakExample { speaker.stopLoop() }
                } label: {
                    Image(systemName: autoSpeakExample ? "speaker.wave.3.fill" : "speaker.slash.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.indigo)
                }
                .buttonStyle(.plain)
            }

            if let example = word.example, !example.isEmpty {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 14) {
                    ForEach(exampleSegments(example)) { segment in
                        segmentView(segment)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)

                HStack(spacing: 14) {
                    Button {
                        Speech.shared.speak(
                            example,
                            rate: store.settings.speechRate,
                            audioKey: exampleAudioKey(word)
                        )
                    } label: {
                        Label("发音", systemImage: "speaker.wave.2.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.indigo)

                    Button {
                        speaker.speak(
                            SpeechLine(example, audioKey: exampleAudioKey(word)),
                            rate: max(0.30, store.settings.speechRate - 0.15)
                        )
                    } label: {
                        Label("慢速", systemImage: "tortoise.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.indigo)

                    Button {
                        store.toggleFavorite(word)
                    } label: {
                        Label("收藏", systemImage: store.isFavorite(word) ? "star.fill" : "star")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.indigo)

                    Spacer()
                }

                if let zh = word.exampleZh, !zh.isEmpty {
                    HStack(spacing: 8) {
                        Pill(text: word.jlpt, tint: Theme.accent)
                        Text(zh)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text("点句中任意一段，看它自己的意思和例句。")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            } else {
                Text("这个词条还没有例句。")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.top, 4)
    }

    private func exampleSegments(_ example: String) -> [ExampleSegment] {
        JapaneseSegmenter.shared.segment(example)
    }

    /// 例句的真人音频 key：`w-<词条id>-ex`，由「生成真人语音」写入。
    private func exampleAudioKey(_ word: Word) -> String {
        VoicePack.key(forWord: word.id) + "-ex"
    }

    @ViewBuilder
    private func segmentView(_ segment: ExampleSegment) -> some View {
        if segment.kind == .punctuation {
            Text(segment.surface)
                .font(.system(size: 17))
                .foregroundStyle(Color.primary)
                .padding(.bottom, 2)
        } else {
            Button {
                selectedSegment = segment
            } label: {
                VStack(spacing: 3) {
                    Text(segment.reading ?? " ")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(minHeight: 12)

                    Text(segment.surface)
                        .font(.system(size: 17))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 1)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(underlineColor(segment))
                                .frame(height: 1.6)
                                .offset(y: 2)
                        }

                    Text(segment.romaji ?? " ")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(minHeight: 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!segment.isTappable)
        }
    }

    private func underlineColor(_ segment: ExampleSegment) -> Color {
        switch segment.kind {
        case .word, .inflection:
            return Theme.accent.opacity(0.7)
        case .unknownKanji:
            return Color(red: 0.78, green: 0.32, blue: 0.28).opacity(0.75)
        case .other:
            return Theme.muted.opacity(0.4)
        default:
            return Theme.indigo.opacity(0.45)
        }
    }

    // MARK: - 记忆技巧

    private func mnemonicBlock(_ word: Word) -> some View {
        // 依赖一下这个版本号，AI 结果写进缓存后能触发重画。
        let _ = mnemonicVersion

        let local = MnemonicBuilder.local(for: word)
        let ai = MnemonicAI.cached(for: word)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                sectionTitle("记忆技巧")
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
                            .foregroundStyle(Theme.indigo)
                    }
                    .buttonStyle(.plain)
                }
            }

            if local.isEmpty && ai.isEmpty {
                Text("这个词条暂时凑不出可讲的点：词库里没有它的构词、活用或同音线索。")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(local.lines) { line in
                lineView(line)
            }

            ForEach(ai) { line in
                lineView(line)
            }

            if let aiError {
                Text(aiError)
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0.78, green: 0.32, blue: 0.28))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    private func lineView(_ line: MnemonicLine) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(line.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.indigo)
                .frame(width: 30, alignment: .leading)
                .padding(.top, 2)

            Text(line.text)
                .font(.system(size: 14))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
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

    // MARK: - 底部：洗脑 / 下一词

    private func bottomBar(_ word: Word) -> some View {
        VStack(spacing: 6) {
            if speaker.isRunning {
                HStack(spacing: 8) {
                    Text(
                        speaker.isPaused
                            ? "已暂停，点「继续」接着读"
                            : "洗脑中，第 \(min(speaker.completedRounds + 1, speaker.totalRounds))/\(speaker.totalRounds) 遍"
                    )
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)

                    Text("剩余 \(speaker.remainingRounds) 次")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)

                    Spacer()
                }
                .padding(.horizontal, 22)
            }

            HStack(spacing: 10) {
                Button {
                    handleWashTap(word)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: washIcon)
                            .font(.footnote)
                        Text(washTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(speaker.isRunning ? .white : Theme.accent)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(
                        speaker.isRunning ? Theme.accent : Color.clear,
                        in: Capsule()
                    )
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)

                if speaker.isRunning {
                    Button {
                        speaker.stopLoop()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                            .padding(10)
                            .background(Theme.mint.opacity(0.6), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                Button {
                    next(word)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right")
                            .font(.footnote)
                        Text("下一词")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 13)
                    .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.paper)
    }

    private var washTitle: String {
        switch speaker.phase {
        case .idle: return "洗脑"
        case .speaking: return "暂停"
        case .paused: return "继续"
        }
    }

    private var washIcon: String {
        switch speaker.phase {
        case .idle: return "repeat"
        case .speaking: return "pause.fill"
        case .paused: return "play.fill"
        }
    }

    private func handleWashTap(_ word: Word) {
        switch speaker.phase {
        case .idle:
            var lines = [SpeechLine(word.reading, audioKey: VoicePack.key(forWord: word.id))]
            if let example = word.example, !example.isEmpty {
                lines.append(SpeechLine(example, audioKey: exampleAudioKey(word)))
            }
            speaker.startLoop(lines, rounds: washRounds, rate: store.settings.speechRate)
        case .speaking, .paused:
            speaker.togglePause()
        }
    }

    private var finishView: some View {
        VStack(spacing: 16) {
            EmptyHint(
                icon: "checkmark.seal",
                title: queue.isEmpty ? "当前词本是空的" : "这一轮走完了",
                detail: queue.isEmpty
                    ? "先在词本里选一个有词的级别。"
                    : "本轮共 \(goodCount) 个按「记得」推进，点下方重新开始。"
            )
            Button("重新开始") {
                start()
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
        }
        .padding(.horizontal, 24)
    }

    // MARK: - 流程

    private func next(_ word: Word) {
        speaker.stopLoop()
        store.grade(word: word, grade: .good)
        goodCount += 1
        if index + 1 >= queue.count {
            done = true
        } else {
            index += 1
        }
    }

    // MARK: - 小标题

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.indigo)
            .padding(.bottom, 3)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.accent)
                    .frame(height: 1.6)
            }
    }
}
