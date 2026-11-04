import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var store: Store

    @State private var queue: [Word] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var phase: Phase = .idle
    @State private var counts = SessionCounts()
    @State private var showList = false

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
                Theme.paper.ignoresSafeArea()

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
                        if word.example != nil {
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
                Capsule()
                    .fill(Theme.mint)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(6, geo.size.width * progress))
            }
        }
        .frame(height: 6)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var progress: CGFloat {
        guard !queue.isEmpty else { return 0 }
        return CGFloat(index) / CGFloat(queue.count)
    }

    private func titleBlock(_ word: Word) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(word.term)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text("\(word.reading)  |  \(word.romaji)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }

            Spacer(minLength: 8)

            HStack(spacing: 14) {
                Button {
                    store.toggleFavorite(word)
                } label: {
                    Image(systemName: store.isFavorite(word) ? "star.fill" : "star")
                        .foregroundStyle(store.isFavorite(word) ? Theme.accent : Theme.muted)
                }
                .buttonStyle(.plain)

                Button {
                    revealed.toggle()
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
                Speech.shared.speak(word.reading, rate: store.settings.speechRate)
            }
            capsule("慢速", icon: "tortoise.fill") {
                Speech.shared.speak(word.reading, rate: max(0.30, store.settings.speechRate - 0.15))
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
            .foregroundStyle(Theme.indigo)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.mint.opacity(0.55), in: Capsule())
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
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 6) {
                        Pill(text: word.partOfSpeech, tint: Theme.indigo)
                        Pill(text: word.jlpt, tint: Theme.accent)
                    }
                } else {
                    Text("点击查看词义")
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 96)
            .padding(12)
            .background(Theme.mint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func exampleBlock(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("单词例句")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.indigo)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(height: 1.6)
                }

            if let example = word.example {
                Text(example)
                    .font(.system(size: 17))
                    .lineSpacing(4)
            }

            if let zh = word.exampleZh {
                Text(zh)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }

            HStack(spacing: 14) {
                Button {
                    Speech.shared.speak(word.example ?? word.reading, rate: store.settings.speechRate)
                } label: {
                    Label("发音", systemImage: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.indigo)
                }
                .buttonStyle(.plain)

                Button {
                    store.toggleFavorite(word)
                } label: {
                    Label("收藏", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.indigo)
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
                        .padding(.vertical, 9)
                        .background(tint(grade).opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(tint(grade))
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
                .foregroundStyle(Theme.indigo)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                pick(.good)
            } label: {
                HStack(spacing: 5) {
                    Text("下一词")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(Theme.accent.opacity(revealed ? 1 : 0.35), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!revealed)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.paper)
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
                        .foregroundStyle(Theme.accent)
                    Text("这一轮结束了")
                        .font(.title3.weight(.semibold))
                    Text("共 \(counts.total) 张 · 记得 \(counts.good + counts.easy) · 模糊 \(counts.hard) · 忘了 \(counts.again)")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }

            Spacer(minLength: 0)

            Button {
                start()
            } label: {
                Text("再来一轮")
            }
            .buttonStyle(PrimaryButtonStyle(fill: Theme.accent))

            Text("忘了的词会在 10 分钟后再出现。")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
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
        case .again: return Color(red: 0.78, green: 0.32, blue: 0.28)
        case .hard: return Color(red: 0.72, green: 0.52, blue: 0.20)
        case .good: return Theme.accent
        case .easy: return Theme.jade
        }
    }

    private func pick(_ grade: ReviewGrade) {
        guard let word = current else { return }
        store.grade(word: word, grade: grade)
        counts.record(grade)

        if grade == .again, queue.count < 200 {
            queue.append(word)
        }

        revealed = false
        if index + 1 >= queue.count {
            index = queue.count
            withAnimation(.easeOut(duration: 0.2)) { phase = .done }
        } else {
            withAnimation(.easeInOut(duration: 0.18)) { index += 1 }
        }
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
                                Text("｜")
                                    .foregroundStyle(Theme.muted)
                                Text(word.reading)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.muted)
                            }

                            tagRow("日文", word.term)
                            tagRow("中文", word.meaning)

                            if offset == currentIndex {
                                Text("点击查看词义")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Theme.mint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Rectangle()
                            .fill(Theme.hairline.opacity(0.4))
                            .frame(height: 0.6)
                            .padding(.leading, 16)
                    }
                }
            }
            .background(Theme.paper.ignoresSafeArea())
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
                .foregroundStyle(Theme.indigo)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.mint, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
