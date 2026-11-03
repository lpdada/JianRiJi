import SwiftUI

struct KanaChartView: View {
    @State private var mode: KanaMode = .seion
    @State private var showKatakana = false
    @State private var lastSpoken: String?

    enum KanaMode: String, CaseIterable, Identifiable {
        case seion = "清音"
        case dakuten = "浊音"
        case yoon = "拗音"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .seion: return "speaker.wave.2.fill"
            case .dakuten: return "waveform"
            case .yoon: return "music.note"
            }
        }

        var rows: [[Kana]] {
            switch self {
            case .seion: return KanaData.seion
            case .dakuten: return KanaData.dakuten + KanaData.handakuten
            case .yoon: return KanaData.yoon
            }
        }

        /// 摊平成一串，占位符也保留，保证行列不塌。
        var cells: [Kana] { rows.flatMap { $0 } }

        var columns: Int { self == .yoon ? 3 : 5 }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: mode.columns)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    modeTabs
                    grid
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("五十音")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottom) {
                katakanaToggle
                    .padding(.bottom, 14)
            }
        }
        .onChange(of: mode) { _ in
            lastSpoken = nil
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("探索日语发音的乐趣！")
                .font(.system(size: 17, weight: .semibold))
            Text("学习地道的日语发音，准确的表达日语")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var modeTabs: some View {
        HStack(spacing: 0) {
            ForEach(KanaMode.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { mode = item }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 11))
                            Text(item.rawValue)
                                .font(.subheadline.weight(mode == item ? .semibold : .regular))
                        }
                        .foregroundStyle(mode == item ? Theme.accent : Theme.muted)

                        Rectangle()
                            .fill(mode == item ? Theme.accent : Color.clear)
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
    }

    private var grid: some View {
        LazyVGrid(columns: gridColumns, spacing: 8) {
            ForEach(Array(mode.cells.enumerated()), id: \.offset) { _, kana in
                if kana.isPlaceholder {
                    Color.clear.frame(height: 62)
                } else {
                    cell(kana)
                }
            }
        }
    }

    private func cell(_ kana: Kana) -> some View {
        Button {
            Speech.shared.speak(kana.kana, rate: 0.42)
            lastSpoken = kana.kana
        } label: {
            VStack(spacing: 3) {
                Text(glyph(kana.kana))
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundStyle(lastSpoken == kana.kana ? Theme.accent : Color.primary)
                Text(kana.romaji)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(Theme.mint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func glyph(_ kana: String) -> String {
        guard showKatakana else { return kana }
        return KanaData.katakanaMap[kana] ?? kana
    }

    private var katakanaToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { showKatakana.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
                Text("片假名")
                    .font(.footnote.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Theme.accent, in: Capsule())
            .shadow(color: Theme.accent.opacity(0.25), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}
