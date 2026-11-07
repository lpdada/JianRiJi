//  HomeDashboardView.swift
//  新「首页」Dashboard
//  对应设计稿: home-and-books.png 左屏
//
//  结构（自上而下）：
//   1. 查词搜索 + 五十音入口
//   2. 当前词本 Hero 卡（进度 / 等待复习 / 今日新词 / 开始背词 / 右上切换）
//   3. 快速背词 + 背语法 两个快捷入口
//   4. 常用功能：我的生词 / 复习记录 / 连连看
//   5. 其他功能：五十音图 / 随身听 / 语音包
//   6. RootView TabBar：首页 / 词本 / 我的
//
//  数据由 RootView 从 Store 算好传入（DashboardState），本视图只负责展示与回调。

import SwiftUI

// MARK: - 视图数据（RootView 从现有 Store 生成）

struct DashboardState {
    var bookTitle: String
    var bookBadge: String
    var bookTint: Int
    var learned: Int
    var total: Int
    var dueCount: Int        // 等待复习（SRS 到期）
    var newTarget: Int       // 今日新词上限（默认 20）
    var lastWord: String?    // 上次学到：「営業（えいぎょう）」

    var progress: Double {
        total > 0 ? Double(learned) / Double(total) : 0
    }
}

struct HomeDashboardView: View {
    let state: DashboardState
    var onStartStudy: () -> Void = {}
    var onSwitchBook: () -> Void = {}          // 跳词本页
    var onQuickWords: () -> Void = {}          // 快速背词（今日队列速刷）
    var onGrammar: () -> Void = {}             // 背语法
    var onWordBooks: () -> Void = {}           // 底部词本 Tab 也进这里
    var onSearch: () -> Void = {}              // 查词
    var onKana: () -> Void = {}                // 五十音图
    var onFavorites: () -> Void = {}           // 我的生词（收藏列表）
    var onReviewRecords: () -> Void = {}       // 复习记录（学习页热力图）
    var onConnect: () -> Void = {}             // 连连看
    var onListen: () -> Void = {}              // 随身听
    var onVoicePack: () -> Void = {}           // 语音包设置

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                statusBarSpacer
                searchRow
                heroCard
                    .padding(.top, 6)
                quickRow
                    .padding(.top, 14)
                sectionTitle("常用功能")
                    .padding(.top, 22)
                functionGrid(first: true)
                sectionTitle("其他功能", top: 16)
                functionGrid(first: false)
                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 16)
        }
        .background(AppTheme.screenGradient.ignoresSafeArea())
    }

    private var statusBarSpacer: some View {
        Color.clear.frame(height: 8)
    }

    // MARK: 搜索行

    private var searchRow: some View {
        HStack(spacing: 10) {
            Button(action: onSearch) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.ink3)
                    Text("查词：日文 · 假名 · 中文")
                        .font(.system(size: 14.5))
                        .foregroundColor(AppTheme.ink3)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(height: 42)
                .background(Capsule().fill(AppTheme.card).shadow(color: .black.opacity(0.05), y: 1, blur: 2))
            }
            .buttonStyle(.plain)

            Button(action: onKana) {
                HStack(spacing: 7) {
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.primary)
                    Text("五十音")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(AppTheme.primary)
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Capsule().fill(AppTheme.card).shadow(color: .black.opacity(0.05), y: 1, blur: 2))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    // MARK: Hero 卡（当前词本）

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                BookCoverTile(badge: state.bookBadge, tint: state.bookTint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.bookTitle)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(AppTheme.ink)
                    if let last = state.lastWord {
                        Text("上次学到：\(last)")
                            .font(.system(size: 12.5))
                            .foregroundColor(AppTheme.ink3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Button(action: onSwitchBook) {
                    HStack(spacing: 4) {
                        Text("切换")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.primary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.primary)
                    }
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(state.learned)")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(AppTheme.ink)
                    .monospacedDigit()
                Text("/ \(state.total) 词")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.ink3)
                Spacer()
            }
            .padding(.top, 12)

            HairlineProgressBar(progress: state.progress)
                .padding(.top, 8)
                .frame(height: 6)

            Divider()
                .overlay(AppTheme.hairline)
                .padding(.top, 14)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(state.dueCount)")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(AppTheme.ink)
                        .monospacedDigit()
                    Text("等待复习")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.ink3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(state.newTarget)")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(AppTheme.ink)
                        .monospacedDigit()
                    Text("今日新词")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.ink3)
                }
                .padding(.leading, 22)

                Spacer()

                MainCTAButton(title: "开始背词", icon: "book.fill", action: onStartStudy)
            }
            .padding(.top, 14)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous)
                .fill(AppTheme.card)
                .shadow(color: .black.opacity(0.05), y: 4, blur: 14)
        )
    }

    // MARK: 快速背词 / 背语法

    private var quickRow: some View {
        HStack(spacing: 12) {
            quickTile(icon: "arrow.left.arrow.right", title: "快速背词", action: onQuickWords)
            quickTile(icon: "book", title: "背语法", action: onGrammar)
        }
    }

    private func quickTile(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(AppTheme.primarySoft).frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.primary)
                }
                Text(title)
                    .font(.system(size: 16.5, weight: .bold))
                    .foregroundColor(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: 0xC0CCC6))
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.tileRadius, style: .continuous)
                    .fill(AppTheme.card)
                    .shadow(color: .black.opacity(0.05), y: 4, blur: 12)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 功能区

    private func sectionTitle(_ text: String, top: CGFloat = 22) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .heavy))
            .foregroundColor(AppTheme.ink)
            .padding(.leading, 4)
            .padding(.top, top)
    }

    @ViewBuilder
    private func functionGrid(first: Bool) -> some View {
        HStack(spacing: 10) {
            if first {
                functionTile(systemIcon: "heart", label: "我的生词", action: onFavorites)
                functionTile(systemIcon: "calendar", label: "复习记录", action: onReviewRecords)
                functionTile(systemIcon: "square.on.square", label: "连连看", action: onConnect)
            } else {
                functionTile(systemIcon: "character.book.closed", label: "五十音图", action: onKana)
                functionTile(systemIcon: "headphones", label: "随身听", action: onListen)
                functionTile(systemIcon: "speaker.wave.2", label: "语音包", action: onVoicePack)
            }
        }
    }

    private func functionTile(systemIcon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                SoftIcon(systemName: systemIcon, size: 44, iconSize: 20,
                         iconColor: AppTheme.primary, bg: AppTheme.primarySoft)
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.ink2)
            }
            .frame(height: 96)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.tileRadius, style: .continuous)
                    .fill(AppTheme.card)
                    .shadow(color: .black.opacity(0.04), y: 4, blur: 12)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 墨绿大按钮（开始背词 / 下一词 复用）

struct MainCTAButton: View {
    let title: String
    var icon: String? = nil
    var height: CGFloat = 56
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 26)
            .frame(height: height)
            .background(
                Capsule().fill(
                    LinearGradient(colors: [AppTheme.primaryPressed, AppTheme.primaryDeep],
                                   startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: AppTheme.primary.opacity(0.28), y: 6, blur: 16)
            )
        }
        .buttonStyle(.plain)
    }
}
