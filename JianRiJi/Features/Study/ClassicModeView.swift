import SwiftUI

/// 经典模式：参考截图的大字词卡布局，只用本地数据，不造假社区 / 真人 / AI 功能。
/// - 大字词形 + 假名 ・ romaji，顶部收藏星；
/// - 发音 / 慢速（系统 TTS，无真人语音）；词性 + 中文释义直接展示（不翻面）；
/// - 参考例句：有分段注音时按段三行（读音 / 词形 / romaji）流式排布，
///   只有整句读音时整句显示读音与 romaji；例句中文与 JLPT 标签在下；
/// - 洗脑：循环念当前词的读音 + 例句，不换词；下一词：按“记得”记分并前进。
struct ClassicModeView: View {
    @EnvironmentObject private var store: Store

    @State private var queue: [Word] = []
    @State private var index = 0
    @State private var done = false
    @State private var goodCount = 0
    @State private var washing = false
    @State private var washTask: Task<Void, Never>?
    @State private var showList = false
    @State private var showDetail = false

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
                            if let note = word.note, !note.isEmpty {
                                noteBlock(note)
                            }
                            referenceExample(word)
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
                        stopWash()
                        start()
                    } label: {
                        Label("重新开始", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        stopWash()
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
            if queue.isEmpty { start() }
        }
        .onDisappear {
            stopWash()
        }
        .sheet(isPresented: $showList) {
            QueueListView(queue: queue, currentIndex: index, title: store.currentDeckTitle)
        }
        .sheet(isPresented: $showDetail) {
            if let word = current {
                WordDetailView(word: word)
            }
        }
    }

    private func start() {
        queue = store.sessionQueue()
        index = 0
        done = false
        goodCount = 0
        washing = false
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
                    Speech.shared.speak(word.reading, rate: store.settings.speechRate)
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
                Speech.shared.speak(word.reading, rate: store.settings.speechRate)
            }
            capsule("慢速", icon: "tortoise.fill") {
                Speech.shared.speak(word.reading, rate: max(0.30, store.settings.speechRate - 0.15))
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
            HStack(spacing: 8) {
                Pill(text: word.partOfSpeech, tint: Theme.indigo)
                Text(word.meaning)
                    .font(.system(size: 20, weight: .semibold))
            }
            Text("中文释义直接展示，不翻面；日文释义词库里没有，不编造。")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        }
    }

    private func noteBlock(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("解析")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.indigo)
            Text(note)
                .font(.system(size: 16))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 14)
    }

    private func referenceExample(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("参考例句")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.indigo)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(height: 1.6)
                }

            if let example = word.example {
                if let furigana = word.exampleFurigana, !furigana.isEmpty {
                    let segments = AnnotatedExample.parse(furigana)
                    if !segments.isEmpty {
                        FlowLayout(horizontalSpacing: 8, verticalSpacing: 12) {
                            ForEach(segments) { segment in
                                VStack(spacing: 2) {
                                    Text(segment.reading ?? "")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.muted)
                                        .frame(minHeight: 12)
                                    Text(segment.text)
                                        .font(.system(size: 17))
                                        .underline()
                                    Text(segment.romaji ?? "")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.muted)
                                        .frame(minHeight: 12)
                                }
                            }
                        }
                    } else {
                        // 整句读音：读音一行、词形一行、romaji 一行
                        VStack(alignment: .leading, spacing: 4) {
                            Text(furigana)
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                            Text(example)
                                .font(.system(size: 17))
                                .lineSpacing(4)
                            Text(KanaRomaji.romaji(for: furigana))
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                } else {
                    Text(example)
                        .font(.system(size: 17))
                        .lineSpacing(4)
                }

                HStack(spacing: 14) {
                    Button {
                        Speech.shared.speak(example, rate: store.settings.speechRate)
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

            if let zh = word.exampleZh {
                HStack(spacing: 8) {
                    Pill(text: word.jlpt, tint: Theme.accent)
                    Text(zh)
                        .font(.subheadline)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - 底部：洗脑 / 下一词

    private func bottomBar(_ word: Word) -> some View {
        HStack(spacing: 12) {
            Button {
                washing ? stopWash() : startWash(word)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "repeat")
                        .font(.footnote)
                    Text(washing ? "停止洗脑" : "洗脑")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(washing ? .white : Theme.accent)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(
                    washing ? Theme.accent : Color.clear,
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)

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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.paper)
    }

    private var finishView: some View {
        VStack(spacing: 16) {
            EmptyHint(
                icon: "checkmark.seal",
                title: queue.isEmpty ? "当前词本是空的" : "这一轮走完了",
                detail: queue.isEmpty ? "先在词本里选一个有词的级别。" : "本轮共 \(goodCount) 个按“记得”推进，点下方重新开始。"
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
        stopWash()
        store.grade(word: word, grade: .good)
        goodCount += 1
        if index + 1 >= queue.count {
            done = true
        } else {
            index += 1
        }
    }

    private func startWash(_ word: Word) {
        Speech.shared.activateSession()
        washing = true
        washTask?.cancel()
        washTask = Task { @MainActor in
            while washing && !Task.isCancelled {
                Speech.shared.speak(word.reading, rate: store.settings.speechRate)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard washing else { break }
                if let example = word.example {
                    Speech.shared.speak(example, rate: store.settings.speechRate)
                    // 系统 TTS 这里没有播完回调，等待按例句长度估算（约每字 0.25 秒 + 1 秒），
                    // 长例句宁可多等一拍，也不在中途截断；随时点“停止洗脑”可停。
                    let wait = Double(example.count) * 0.25 + 1.0
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                }
                guard washing else { break }
            }
            washing = false
        }
    }

    private func stopWash() {
        washing = false
        washTask?.cancel()
        washTask = nil
        Speech.shared.stop()
    }
}
