import SwiftUI

/// 经典复习：看词形回忆词义，翻面后四档评分。
///
/// 修了：
///  1. **主题分裂**。这个界面走的是旧 `Theme.swift`，首页和词本走 `AppTheme`，
///     用户从首页点进来会看到两套完全不同的视觉语言。现在统一到 `AppTheme`。
///  2. **「忘了」会被惩罚两次**。答错后这个词被追加到本轮末尾，用户再答一次又会
///     `store.grade(.again)` —— level 再降两级、ease 再掉 0.2。一轮里同一张卡最多评一次。
///  3. **「下一词」等于「记得」**。底部那个按钮和上方四档里的「记得」是同一个动作，
///     却长得像「跳过」。改成真正的跳过（不评分）。
///  4. 进度条最后一题到不了 100%；翻面前就把 `romaji` 摆出来了，等于给了读音提示。
struct ReviewView: View {
    @EnvironmentObject private var store: Store

    @State private var queue: [Word] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var phase: Phase = .idle
    @State private var counts = SessionCounts()
    @State private var showList = false
    /// 本轮已经评过分的词。防止「忘了」回到队尾后被二次惩罚。
    @State private var gradedThisRound: Set<String> = []

    enum Phase {
        case idle, running, done
    }

    struct SessionCounts {
        var again = 0
        var hard = 0
        var good = 0
        var easy = 0

        var total: Int { again + hard + good + easy }

        mutating func record(_ grade: ReviewGrade) {
            switch grade {
            case .again: again += 1
            case .hard: hard += 1
            case .good: good += 1
            case .easy: easy += 1
            }
        }
    }

    private var current: Word? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    var body: some View {
        ZStack {
            AppTheme.bgMint.ignoresSafeArea()

            switch phase {
            case .running:
                runningView
            case .idle, .done:
                finishView
            }
        }
        .navigationTitle(store.currentBookTitle)
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
                        Speech.shared.stop()
                        start()
                    } label: {
                        Label("重新开始", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        Speech.shared.stop()
                        phase = .done
                    } label: {
                        Label("结束本轮", systemImage: "xmark")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .onAppear {
            if phase == .idle { start() }
        }
        .sheet(isPresented: $showList) {
            QueueListView(queue: queue, currentIndex: index, title: store.currentBookTitle)
        }
    }

    // MARK: - 卡片

    @ViewBuilder
    private var runningView: some View {
        if let word = current {
            VStack(spacing: 0) {
                progressBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        titleBlock(word)
                        actionPills(word)
                        meaningBlock(word)
                        if revealed, word.example != nil {
                            exampleBlock(word)
                        }
                        if revealed {
                            gradeRow
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }

                bottomBar
            }
        } else {
            EmptyHint(icon: "checkmark.seal", title: "这一轮走完了", detail: "点右上角重新开始。")
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.track)
                Capsule()
                    .fill(AppTheme.primary)
                    .frame(width: max(6, geo.size.width * progress))
            }
        }
        .frame(height: 6)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// 把「当前这题也算半格」算进去，最后一题能到 100%。
    private var progress: CGFloat {
        guard !queue.isEmpty else { return 0 }
        let answered = CGFloat(index) + (revealed ? 0.5 : 0)
        return min(1, answered / CGFloat(queue.count))
    }

    private func titleBlock(_ word: Word) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(word.term)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                // 翻面前不显示读音和 romaji：这张卡练的是「看汉字想意思」，
                // 预先给出读音等于泄题（romaji 更是纯噪音）。
                if revealed {
                    Text("\(word.reading)  |  \(word.romaji)")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink3)
                } else {
                    Text("先想一下它的意思，再点下面的卡片")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink3)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 14) {
                Button {
                    store.toggleFavorite(word)
                } label: {
                    Image(systemName: store.isFavorite(word) ? "star.fill" : "star")
                        .foregroundStyle(store.isFavorite(word) ? AppTheme.primary : AppTheme.ink3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.isFavorite(word) ? "取消收藏" : "收藏")

                if store.canUndoGrade {
                    Button {
                        undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .foregroundStyle(AppTheme.ink3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("撤销上一次评分")
                }
            }
            .font(.system(size: 17))
        }
    }

    private func actionPills(_ word: Word) -> some View {
        HStack(spacing: 8) {
            if revealed {
                capsule("发音", icon: "speaker.wave.2.fill") {
                    Speech.shared.speak(word.reading, rate: store.settings.speechRate)
                }
                capsule("慢速", icon: "tortoise.fill") {
                    Speech.shared.speak(word.reading, rate: max(0.30, store.settings.speechRate - 0.15))
                }
            }
            capsule("收藏", icon: "star.fill") {
                store.toggleFavorite(word)
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
            .foregroundStyle(AppTheme.ink2)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AppTheme.primarySoft, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func meaningBlock(_ word: Word) -> some View {
        Button {
            reveal(word)
        } label: {
            VStack(spacing: 6) {
                if revealed {
                    Text(word.meaning)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 6) {
                        Pill(text: word.partOfSpeech, tint: AppTheme.ink2)
                        Pill(text: word.jlpt, tint: AppTheme.primary)
                    }
                } else {
                    Text("点击查看词义")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 96)
            .padding(12)
            .background(AppTheme.primarySoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func exampleBlock(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("单词例句")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.ink2)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AppTheme.primary)
                        .frame(height: 1.6)
                }

            if let example = word.example {
                Text(example)
                    .font(.system(size: 17))
                    .foregroundStyle(AppTheme.ink)
                    .lineSpacing(4)
            }

            if let zh = word.exampleZh {
                Text(zh)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink3)
            }

            HStack(spacing: 14) {
                Button {
                    Speech.shared.speak(word.example ?? word.reading, rate: store.settings.speechRate)
                } label: {
                    Label("发音", systemImage: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink2)
                }
                .buttonStyle(.plain)

                Button {
                    store.toggleFavorite(word)
                } label: {
                    Label("收藏", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink2)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.top, 4)
    }

    private var gradeRow: some View {
        HStack(spacing: 8) {
            ForEach(ReviewGrade.allCases) { grade in
                Button {
                    pick(grade)
                } label: {
                    Text(grade.title)
                        .font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(tint(grade).opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(tint(grade))
                .accessibilityLabel("\(grade.title)：\(grade.subtitle)")
            }
        }
        .padding(.top, 4)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                showList = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "list.bullet")
                        .font(.footnote)
                    Text("列表")
                        .font(.subheadline)
                }
                .foregroundStyle(AppTheme.ink2)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .overlay(Capsule().strokeBorder(AppTheme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            // 跳过：不评分，只是往下走。原来这里是「下一词」但按的是 .good，
            // 和上方四档里的「记得」重复，却长得像跳过。
            Button {
                skip()
            } label: {
                HStack(spacing: 5) {
                    Text("跳过")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(AppTheme.ink2)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(AppTheme.primarySoft, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("不评分，这张卡保持当前记忆状态")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.bgMint)
    }

    // MARK: - 结算

    private var finishView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            if counts.total == 0 && queue.isEmpty {
                EmptyHint(
                    icon: "moon.zzz",
                    title: "今天已经清空了",
                    detail: "没到期就没有新东西——休息也是复习的一部分。"
                )
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(AppTheme.primary)
                    Text("这一轮结束了")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("共 \(counts.total) 张 · 记得 \(counts.good + counts.easy) · 模糊 \(counts.hard) · 忘了 \(counts.again)")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink3)
                }
            }

            Spacer(minLength: 0)

            Button {
                start()
            } label: {
                Text("再来一轮")
            }
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.primary))

            Text("忘了的词会回到本轮末尾再过一次；记忆曲线已经把它排到 10 分钟后。")
                .font(.caption2)
                .foregroundStyle(AppTheme.ink3)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    // MARK: - 行为

    private func start() {
        store.bootstrap()
        queue = store.sessionQueue()
        index = 0
        revealed = false
        counts = SessionCounts()
        gradedThisRound.removeAll()
        phase = queue.isEmpty ? .done : .running
    }

    private func reveal(_ word: Word) {
        guard !revealed else { return }
        withAnimation(.easeOut(duration: 0.18)) { revealed = true }
        if store.settings.autoSpeak {
            Speech.shared.speak(word.reading, rate: store.settings.speechRate)
        }
    }

    private func tint(_ grade: ReviewGrade) -> Color {
        switch grade {
        case .again: return AppTheme.danger
        case .hard: return AppTheme.warning
        case .good: return AppTheme.primary
        case .easy: return AppTheme.success
        }
    }

    private func pick(_ grade: ReviewGrade) {
        guard let word = current else { return }

        // 同一张卡本轮只评一次：不然「忘了」回到队尾再答一次，会被罚第二遍。
        if !gradedThisRound.contains(word.id) {
            store.grade(word: word, grade: grade)
            counts.record(grade)
            gradedThisRound.insert(word.id)
        }

        // 忘了的词回到队尾再过一遍（只是复习，不重复记分）。
        if grade == .again,
           queue.count < 200,
           !queue.dropLast().contains(where: { $0.id == word.id }) {
            queue.append(word)
        }

        advance()
    }

    private func skip() {
        advance()
    }

    private func advance() {
        revealed = false
        if index + 1 >= queue.count {
            index = queue.count
            withAnimation(.easeOut(duration: 0.2)) { phase = .done }
        } else {
            withAnimation(.easeInOut(duration: 0.18)) { index += 1 }
        }
    }

    private func undo() {
        guard store.undoLastGrade() else { return }
        if index > 0 { index -= 1 }
        revealed = false
        if let word = current {
            gradedThisRound.remove(word.id)
        }
        phase = .running
    }
}

/// 「列表速过」：整轮队列摊平，当前项高亮。
struct QueueListView: View {
    let queue: [Word]
    let currentIndex: Int
    let title: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(queue.enumerated()), id: \.offset) { offset, word in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(word.meaning)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Text("｜")
                                    .foregroundStyle(AppTheme.ink3)
                                Text(word.reading)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.ink3)
                            }

                            tagRow("日文", word.term)
                            tagRow("中文", word.meaning)

                            if offset == currentIndex {
                                Text("当前这一张")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(AppTheme.primarySoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Rectangle()
                            .fill(AppTheme.hairline)
                            .frame(height: 0.6)
                            .padding(.leading, 16)
                    }
                }
            }
            .background(AppTheme.bgMint.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func tagRow(_ tag: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(tag)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.ink2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppTheme.primarySoft, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(text)
                .font(.footnote)
                .foregroundStyle(AppTheme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
