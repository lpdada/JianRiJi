import SwiftUI

struct StudyHubView: View {
    @EnvironmentObject private var store: Store

    @State private var path = NavigationPath()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    todayCard
                    HeatmapView(log: store.log)
                    grammarCard
                    modeGrid
                    note
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("学习")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: StudyMode.self) { mode in
                destination(for: mode)
            }
        }
    }

    @ViewBuilder
    private func destination(for mode: StudyMode) -> some View {
        switch mode {
        case .review: ReviewView()
        case .kanaJudge: KanaJudgeView()
        case .spell: SpellModeView()
        case .connect: LianliankaView()
        case .listen: SuishentingView()
        case .handwriting: HandwritingView()
        }
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.currentDeckTitle)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("今日 \(store.reviewedToday) 张")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            HStack(spacing: 0) {
                StatBlock(value: "\(store.remainingDueCount)", label: "待复习", tint: Theme.accent)
                Divider().frame(height: 26)
                StatBlock(value: "\(min(store.newAllowance, store.freshWords.count))", label: "新词", tint: Theme.jade)
                Divider().frame(height: 26)
                StatBlock(value: "\(store.masteredCount)", label: "已掌握", tint: Theme.indigo)
            }

            ProgressView(value: store.todayProgress)
                .tint(Theme.accent)
        }
        .paperCard(padding: 16)
    }

    /// 语法学习入口：不新开底部 Tab（6 个 Tab 会挤进“更多”里），放在学习页最显眼的位置。
    private var grammarCard: some View {
        NavigationLink {
            GrammarView()
                .environmentObject(store)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "book")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.indigo)
                    .frame(width: 36, height: 36)
                    .background(Theme.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("语法学习")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text("\(store.grammarPoints.count) 个分级语法点，N5–N1，按级别筛选可搜")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var modeGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(StudyMode.allCases) { mode in
                NavigationLink(value: mode) {
                    modeCard(mode)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func modeCard(_ mode: StudyMode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: mode.icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(tint(mode))
                .frame(width: 36, height: 36)
                .background(tint(mode).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(mode.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)

            Text(mode.subtitle)
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func tint(_ mode: StudyMode) -> Color {
        switch mode {
        case .review: return Theme.accent
        case .kanaJudge: return Theme.indigo
        case .spell: return Color(red: 0.72, green: 0.52, blue: 0.20)
        case .connect: return Theme.jade
        case .listen: return Color(red: 0.36, green: 0.42, blue: 0.70)
        case .handwriting: return Color(red: 0.20, green: 0.55, blue: 0.45)
        }
    }

    private var note: some View {
        Text("每个模式都写进同一套记忆曲线，练完都会推进度；随身听只连播，不改状态。")
            .font(.caption2)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
