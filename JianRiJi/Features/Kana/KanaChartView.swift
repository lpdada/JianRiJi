import SwiftUI

struct KanaChartView: View {
    @State private var mode: KanaMode = .seion
    @State private var showRomaji = true
    @State private var showKatakana = false
    @State private var lastSpoken: String?

    enum KanaMode: String, CaseIterable, Identifiable {
        case seion = "清音"
        case dakuten = "浊音"
        case handakuten = "半浊音"
        case yoon = "拗音"

        var id: String { rawValue }

        var rows: [[Kana]] {
            switch self {
            case .seion: return KanaData.seion
            case .dakuten: return KanaData.dakuten
            case .handakuten: return KanaData.handakuten
            case .yoon: return KanaData.yoon
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    controls
                    grid
                    note
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("五十音")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: mode) { _ in
            lastSpoken = nil
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("分组", selection: $mode) {
                ForEach(KanaMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 16) {
                Toggle("罗马字", isOn: $showRomaji)
                    .font(.footnote)
                Toggle("片假名", isOn: $showKatakana)
                    .font(.footnote)
            }
            .toggleStyle(.switch)
        }
        .paperCard(padding: 14)
    }

    private var grid: some View {
        VStack(spacing: 8) {
            ForEach(mode.rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(Array(mode.rows[rowIndex].enumerated()), id: \.offset) { _, kana in
                        if kana.isPlaceholder {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 58)
                        } else {
                            cell(kana)
                        }
                    }
                }
            }
        }
        .paperCard(padding: 12)
    }

    private func cell(_ kana: Kana) -> some View {
        Button {
            Speech.shared.speak(kana.kana, rate: 0.42)
            lastSpoken = kana.kana
        } label: {
            VStack(spacing: 2) {
                Text(glyph(kana.kana))
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(lastSpoken == kana.kana ? Theme.accent : Color.primary)
                if showRomaji {
                    Text(kana.romaji)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func glyph(_ kana: String) -> String {
        guard showKatakana else { return kana }
        return KanaData.katakanaMap[kana] ?? kana
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("点一下听发音，念准了再往下走。")
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Text("这里没做笔顺动画——你要是想练写，找张纸临一遍，比看动画管用。")
                .font(.caption2)
                .foregroundStyle(Theme.muted.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
