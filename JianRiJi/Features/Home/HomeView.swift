import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: Store
    @Binding var selection: RootTab

    @State private var showDictation = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "早上好"
        case 11..<14: return "中午好"
        case 14..<18: return "下午好"
        case 18..<23: return "晚上好"
        default: return "夜深了"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    todayCard
                    primaryActions
                    statRow
                    weekSection
                    footerNote
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("简日记")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showDictation) {
            DictationView()
                .environmentObject(store)
        }
    }

    // MARK: - 今天

    private var todayCard: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(greeting)，慢慢来。")
                    .font(.title3.weight(.semibold))

                Text(DateText.monthDay.string(from: Date()))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)

                HStack(spacing: 6) {
                    Pill(text: "待复习 \(store.remainingDueCount)", tint: Theme.accent)
                    Pill(text: "新词 \(min(store.newAllowance, store.freshWords.count))", tint: Theme.jade)
                    if store.streak > 0 {
                        Pill(text: "连 \(store.streak) 天", tint: Theme.indigo)
                    }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 4)

            VStack(spacing: 6) {
                ZStack {
                    RingProgress(value: store.todayProgress, lineWidth: 8)
                    Text("\(Int(store.todayProgress * 100))%")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .frame(width: 64, height: 64)

                Text("今日")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
        }
        .paperCard(padding: 16)
    }

    private var primaryActions: some View {
        VStack(spacing: 10) {
            Button {
                selection = .review
            } label: {
                HStack {
                    Image(systemName: "rectangle.stack.fill")
                    Text(store.remainingDueCount + min(store.newAllowance, store.freshWords.count) > 0
                         ? "开始今天的复习"
                         : "加练一轮")
                    Spacer()
                    Text("\(store.remainingDueCount + min(store.newAllowance, store.freshWords.count)) 张")
                        .font(.subheadline.weight(.medium))
                        .opacity(0.85)
                }
                .padding(.horizontal, 16)
            }
            .buttonStyle(PrimaryButtonStyle())

            HStack(spacing: 10) {
                Button {
                    showDictation = true
                } label: {
                    Label("听写", systemImage: "ear")
                }
                .buttonStyle(GhostButtonStyle(tint: Theme.jade))

                Button {
                    selection = .dictionary
                } label: {
                    Label("查词", systemImage: "magnifyingglass")
                }
                .buttonStyle(GhostButtonStyle(tint: Theme.indigo))

                Button {
                    selection = .kana
                } label: {
                    Label("五十音", systemImage: "square.grid.3x3")
                }
                .buttonStyle(GhostButtonStyle(tint: Theme.accent))

                Spacer(minLength: 0)
            }
        }
    }

    private var statRow: some View {
        HStack(spacing: 0) {
            StatBlock(value: "\(store.masteredCount)", label: "已掌握", tint: Theme.jade)
            Divider().frame(height: 28)
            StatBlock(value: "\(store.learningCount)", label: "学习中", tint: Theme.accent)
            Divider().frame(height: 28)
            StatBlock(value: "\(store.totalCount)", label: "词库", tint: Theme.indigo)
        }
        .paperCard(padding: 14)
    }

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近七天")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let accuracy = store.accuracy {
                    Text("正确率 \(Int(accuracy * 100))%")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            WeekBars(data: store.weekCounts)
        }
        .paperCard(padding: 16)
    }

    private var footerNote: some View {
        VStack(spacing: 4) {
            Text("一天二十张，比一口气两百张有用。")
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Text("简日记 v0.1.0 · MIT")
                .font(.caption2)
                .foregroundStyle(Theme.muted.opacity(0.7))
        }
        .padding(.top, 6)
    }
}
