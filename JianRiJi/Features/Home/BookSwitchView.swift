//  BookSwitchView.swift
//  词本切换页 —— 点首页「切换」到达；也是底部 Tab 的「词本」
//  对应设计稿: home-and-books.png 右屏
//
//  数据源 = 打包内置 books.json（字段确认无误）：
//    id / title / badge / categories[常用词单|考试词单|已学词单|生活实用|日常高频]
//    filterType all|book|jlpt|tag|learned|favorite / filterValue / note / tint / author
//
//  说明：
//   · 「正在学习」只有一本，就是 Store 的当前词本（deckFilter）；没有多选状态，
//     点「学习」= 设为当前词本；当前那本的按钮点下去进经典模式开始背。
//   · 旧版 HomeView 里没有「管理」入口，本页也不留管理按钮；App 里没有应用内
//     自定义词单导入工具（导入只在 tools/import_words.py，开发者在电脑上跑），
//     所以底部的自定义词单横条也不留，不留死按钮。

import SwiftUI

// MARK: - 行数据（RootView 用现有词库查询生成 learned / total / studying）

struct BookRowData: Identifiable, Hashable {
    let id: String           // books.json id，如 "jlpt-n3"
    let title: String
    let badge: String
    let tint: Int
    let categories: [String] // books.json categories
    let learned: Int
    let total: Int
    var studying: Bool
    var progress: Double { total > 0 ? Double(learned) / Double(total) : 0 }
}

struct BookSwitchView: View {
    let categories: [String]     // ["已学词单","常用词单","考试词单","生活实用","日常高频"]
    let allBooks: [BookRowData]  // 全词本（含每本进度）
    var selectedCategory: String = "已学词单"   // 默认「已学词单」置顶，与设计稿一致

    var onToggleStudy: (BookRowData) -> Void = { _ in }   // 点「学习」= 设为当前词本
    var onStartStudy: (BookRowData) -> Void = { _ in }    // 当前那本点「学习中」= 开始背

    @Environment(\.dismiss) private var dismiss

    @State private var category: String
    @State private var query: String = ""

    init(categories: [String], allBooks: [BookRowData], selectedCategory: String = "已学词单",
         onToggleStudy: @escaping (BookRowData) -> Void = { _ in },
         onStartStudy: @escaping (BookRowData) -> Void = { _ in }) {
        self.categories = categories
        self.allBooks = allBooks
        self.selectedCategory = selectedCategory
        self.onToggleStudy = onToggleStudy
        self.onStartStudy = onStartStudy
        _category = State(initialValue: selectedCategory)
    }

    private var filtered: [BookRowData] {
        var list = allBooks
        if category == "已学词单" {
            list = list.filter { $0.studying || $0.learned > 0 }
        } else {
            list = list.filter { $0.categories.contains(category) }
        }
        if !query.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }
        return list.sorted { ($0.studying ? 0 : 1, $0.title) < ($1.studying ? 0 : 1, $1.title) }
    }

    private var studyingCount: Int { allBooks.filter(\.studying).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            chips
            banner
                .padding(.top, 14)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(filtered) { book in
                        BookCard(book: book,
                                 onToggle: {
                                     if book.studying {
                                         onStartStudy(book)
                                     } else {
                                         onToggleStudy(book)
                                     }
                                 })
                    }
                    Color.clear.frame(height: 88)
                }
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, 16)
        .background(AppTheme.screenGradient.ignoresSafeArea())
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(AppTheme.ink)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundColor(AppTheme.ink3)
                TextField("搜索词单", text: $query)
                    .font(.system(size: 15))
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(Capsule().fill(AppTheme.card).shadow(color: .black.opacity(0.05), y: 1, blur: 2))
        }
        .padding(.top, 4)
    }

    private var chips: some View {
        SegmentFlowLayout(alignment: .leading, spacing: 10, lineSpacing: 10) {
            ForEach(categories, id: \.self) { c in
                let selected = c == category
                Button(action: { category = c }) {
                    Text(c)
                        .font(.system(size: 15, weight: selected ? .bold : .semibold))
                        .foregroundColor(selected ? .white : Color(hex: 0x5C6D65))
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background(
                            Capsule().fill(selected ? AppTheme.primary : Color(hex: 0xF4F7F5))
                                .shadow(color: selected ? AppTheme.primary.opacity(0.25) : .clear, y: 3, blur: 10)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 0)
    }

    private var banner: some View {
        HStack {
            HStack(spacing: 6) {
                Text("当前").font(.system(size: 15)).foregroundColor(AppTheme.ink2)
                Text("\(studyingCount)").font(.system(size: 19, weight: .heavy)).foregroundColor(AppTheme.primary)
                Text("本词单正在学习").font(.system(size: 15)).foregroundColor(AppTheme.ink2)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.card)
                .shadow(color: .black.opacity(0.05), y: 1, blur: 2)
        )
    }
}

// MARK: - 词卡行

struct BookCard: View {
    let book: BookRowData
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            BookCoverTile(badge: book.badge, tint: book.tint, size: CGSize(width: 56, height: 62))
            VStack(alignment: .leading, spacing: 0) {
                Text(book.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack {
                    Text("\(book.learned) / \(book.total) 词")
                        .font(.system(size: 13.5))
                        .foregroundColor(AppTheme.ink3)
                        .monospacedDigit()
                    Spacer()
                    Text("\(Int(round(book.progress * 100)))%")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(AppTheme.ink3)
                        .monospacedDigit()
                }
                .padding(.top, 5)
                HairlineProgressBar(progress: book.progress)
                    .padding(.top, 8)
                    .frame(height: 6)
            }
            Button(action: onToggle) {
                Text(book.studying ? "学习中" : "学习")
                    .font(.system(size: 14.5, weight: book.studying ? .semibold : .bold))
                    .foregroundColor(book.studying ? Color(hex: 0x94A49C) : AppTheme.primary)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(
                        Capsule().fill(book.studying ? Color(hex: 0xEFF4F1) : AppTheme.primarySoft)
                            .overlay(Capsule().stroke(AppTheme.primarySoftStroke, lineWidth: 1).opacity(book.studying ? 0 : 1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .fill(AppTheme.card)
                .shadow(color: .black.opacity(0.04), y: 3, blur: 10)
        )
    }
}
