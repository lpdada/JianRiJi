import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var store: Store

    @State private var queue: [Word] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var phase: Phase = .idle
    @State private var counts = SessionCounts()

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
        NavigationStack {
            ZStack {
                Theme.paper.ignoresSafeArea()

                switch phase {
                case .running:
                    runningView
                case .idle, .done:
                    finishView
                }
            }
            .navigationTitle("背单词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("结束") {
                        Speech.shared.stop()
                        phase = .done
                    }
                    .disabled(phase != .running)
                    .opacity(phase == .running ? 1 : 0)
                }
            }
        }
        .onAppear {
            if phase == .idle { start() }
        }
    }

    // MARK: - 运行中

    @ViewBuilder
    private var runningView: some View {
        if let word = current {
            VStack(spacing: 12) {
                progressHeader
                cardView(word)

                if revealed {
                    gradeRow
                } else {
                    Button {
                        reveal()
                    } label: {
                        Text("看答案")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        } else {
            EmptyHint(icon: "checkmark.seal", title: "这一轮走完了", detail: "回去点「再来一轮」继续。")
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Text("第 \(min(index + 1, queue.count)) / \(queue.count) 张")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("本轮 \(counts.total) 次")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            ProgressView(value: Double(index), total: Double(max(1, queue.count)))
                .tint(Theme.accent)
        }
    }

    private func cardView(_ word: Word) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Pill(text: word.jlpt, tint: Theme.indigo)
                Pill(text: word.partOfSpeech)
                Spacer()
                Button {
                    Speech.shared.speak(word.reading, rate: store.settings.speechRate)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            Text(word.term)
                .font(.system(size: 62, weight: .medium, design: .rounded))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .multilineTextAlignment(.center)

            if revealed {
                VStack(spacing: 10) {
                    Text(word.reading)
                        .font(.title3)
                        .foregroundStyle(Theme.muted)

                    if store.settings.showRomaji {
                        Text(word.romaji)
                            .font(.footnote)
                            .foregroundStyle(Theme.muted.opacity(0.8))
                    }

                    Divider().padding(.vertical, 2)

                    Text(word.meaning)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)

                    if let example = word.example {
                        VStack(spacing: 4) {
                            Text(example)
                                .font(.footnote)
                            if let zh = word.exampleZh {
                                Text(zh)
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Text("先自己在心里过一遍，再翻开")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .paperCard(padding: 20)
        .contentShape(Rectangle())
        .onTapGesture {
            if !revealed { reveal() }
        }
    }

    private var gradeRow: some View {
        HStack(spacing: 8) {
            ForEach(ReviewGrade.allCases) { grade in
                Button {
                    pick(grade)
                } label: {
                    VStack(spacing: 2) {
                        Text(grade.title)
                            .font(.subheadline.weight(.semibold))
                        Text(grade.subtitle)
                            .font(.system(size: 9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .opacity(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(tint(grade).opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(tint(grade))
            }
        }
    }

    private func tint(_ grade: ReviewGrade) -> Color {
        switch grade {
        case .again: return Theme.accent
        case .hard: return Color.orange
        case .good: return Theme.jade
        case .easy: return Theme.indigo
        }
    }

    // MARK: - 结算

    private var finishView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            if counts.total == 0 && queue.isEmpty {
                EmptyHint(icon: "moon.zzz", title: "今天已经清空了", detail: "没到期就没有新东西——休息也是复习的一部分。")
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Theme.jade)
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
            .buttonStyle(PrimaryButtonStyle())

            Text("忘了的词会在 10 分钟后再出现。")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 16)
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

    private func reveal() {
        guard let word = current else { return }
        withAnimation(.easeOut(duration: 0.2)) { revealed = true }
        if store.settings.autoSpeak {
            Speech.shared.speak(word.reading, rate: store.settings.speechRate)
        }
    }

    private func pick(_ grade: ReviewGrade) {
        guard let word = current else { return }
        store.grade(word: word, grade: grade)
        counts.record(grade)

        // 忘了的，这轮末尾再给一次手感
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
