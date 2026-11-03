import SwiftUI

/// 随身听：把当前词本的词按顺序连播，锁屏/后台也能继续。
/// 随身听模式：连播当前词本，可循环、可调间隔、支持后台音频。
struct SuishentingView: View {
    @EnvironmentObject private var store: Store

    @State private var words: [Word] = []
    @State private var cursor = 0
    @State private var playing = false
    @State private var loop = true
    @State private var speakMeaning = false
    @State private var interval: Double = 3.0
    @State private var task: Task<Void, Never>?

    private var current: Word? {
        words.indices.contains(cursor) ? words[cursor] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    nowPlaying
                    controls
                    settingsCard
                    queuePreview
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("随身听")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if words.isEmpty {
                words = store.scopedWords
            }
        }
        .onDisappear {
            stop()
        }
    }

    private var nowPlaying: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.mint)
                    .frame(width: 108, height: 108)
                Image(systemName: playing ? "waveform" : "headphones")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.accent)
                    .opacity(playing ? 1 : 0.85)
            }
            .padding(.top, 6)

            if let word = current {
                Text(word.term)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text("\(word.reading)  |  \(word.romaji)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)

                Text(word.meaning)
                    .font(.body)
                    .multilineTextAlignment(.center)

                Text("\(cursor + 1) / \(words.count)")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            } else {
                Text("当前词本是空的")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .paperCard(padding: 18)
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button {
                step(-1)
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.indigo)
            }
            .buttonStyle(.plain)

            Button {
                playing ? stop() : play()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(Theme.accent, in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                step(1)
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.indigo)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $loop) {
                Text("循环播放").font(.subheadline)
            }
            .tint(Theme.accent)

            Toggle(isOn: $speakMeaning) {
                Text("念完再念一遍词形").font(.subheadline)
            }
            .tint(Theme.accent)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("间隔").font(.subheadline)
                    Spacer()
                    Text(String(format: "%.1f 秒", interval))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Slider(value: $interval, in: 1.5...8, step: 0.5)
                    .tint(Theme.accent)
            }
        }
        .paperCard(padding: 16)
    }

    private var queuePreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("播放顺序")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.indigo)
                .padding(.bottom, 8)

            ForEach(Array(words.prefix(8).enumerated()), id: \.element.id) { offset, word in
                HStack(spacing: 8) {
                    Text("\(offset + 1)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 18, alignment: .trailing)
                    Text(word.term)
                        .font(.subheadline)
                        .foregroundStyle(offset == cursor ? Theme.accent : Color.primary)
                    Text(word.reading)
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text(word.meaning)
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                .padding(.vertical, 6)

                if offset != min(7, words.count - 1) {
                    Rectangle()
                        .fill(Theme.hairline.opacity(0.35))
                        .frame(height: 0.5)
                }
            }
        }
        .paperCard(padding: 14)
    }

    // MARK: - 播放

    private func play() {
        guard !words.isEmpty else { return }
        Speech.shared.activateSession()
        playing = true
        task?.cancel()
        task = Task { @MainActor in
            while playing && !Task.isCancelled {
                if !words.indices.contains(cursor) { cursor = 0 }
                let word = words[cursor]
                Speech.shared.speak(word.reading, rate: store.settings.speechRate)

                if speakMeaning {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    guard playing else { break }
                    Speech.shared.speak(word.term, rate: store.settings.speechRate)
                }

                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard playing else { break }

                if cursor + 1 >= words.count {
                    if loop {
                        cursor = 0
                    } else {
                        playing = false
                        break
                    }
                } else {
                    cursor += 1
                }
            }
            playing = false
        }
    }

    private func stop() {
        playing = false
        task?.cancel()
        task = nil
        Speech.shared.stop()
    }

    private func step(_ delta: Int) {
        guard !words.isEmpty else { return }
        let next = (cursor + delta + words.count) % words.count
        cursor = next
        if playing {
            task?.cancel()
            task = nil
            playing = false
            play()
        } else {
            if let word = current {
                Speech.shared.speak(word.reading, rate: store.settings.speechRate)
            }
        }
    }
}
