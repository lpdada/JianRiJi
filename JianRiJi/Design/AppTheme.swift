//  AppTheme.swift
//  简日记 · 2024-11 改版设计 tokens & 通用小组件
//  对应设计稿: home-and-books.png / study-and-brainwash.png

import SwiftUI

// MARK: - 设计 tokens（与设计稿逐像素对齐）

enum AppTheme {
    /// 页面渐变浅景底（首页 / 词本 / 学习页背景）
    static let bgTop = Color(hex: 0xE7EFE9)
    static let bgBottom = Color(hex: 0xEEF2EE)
    static var screenGradient: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: UnitPoint(x: 0.25, y: 1))
    }
    /// 洗脑/学习页底部纯色底
    static let bgMint = Color(hex: 0xE9F2EE)

    /// 墨绿主色（按钮、选中 chip、大字词条、下划线强调）
    static let primary = Color(hex: 0x0E6B5A)
    static let primaryDeep = Color(hex: 0x0C5F50)
    static let primaryPressed = Color(hex: 0x137A66)
    /// 淡绿底（图标圆底、tag pill、选中 tab 背景）
    static let primarySoft = Color(hex: 0xDFECE6)
    static let primarySoftStroke = Color(hex: 0xCFE3DA)

    /// 文字三档
    static let ink = Color(hex: 0x1F2A26)
    static let ink2 = Color(hex: 0x57685F)
    static let ink3 = Color(hex: 0x93A49B)

    /// 卡片与进度条
    static let card = Color.white
    static let track = Color(hex: 0xE3EBE6)
    static let hairline = Color(hex: 0xE7ECE9)

    static let cardRadius: CGFloat = 20
    static let heroRadius: CGFloat = 20
    static let tileRadius: CGFloat = 18

}

// MARK: - 词本封面色（books.json 里 tint: 0~3）

extension AppTheme {
    static func coverColor(tint: Int) -> Color {
        switch tint {
        case 0: return Color(hex: 0x3E8E7E)  // 全部词本 · 青绿
        case 1: return Color(hex: 0xD8956B)  // 初级 · 杏
        case 2: return Color(hex: 0xE0564F)  // JLPT/考试 · 红
        case 3: return Color(hex: 0x5B9BD5)  // 高级/测试 · 蓝
        default: return Color(hex: 0x3E8E7E)
        }
    }
}

// MARK: - 通用组件

/// 圆形浅绿图标底 + 绿描边图标（词卡顶部发音按钮、Tiles 图标等）
struct SoftIcon: View {
    var systemName: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 22
    var iconColor: Color = AppTheme.primary
    var bg: Color = AppTheme.primarySoft

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(bg)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(iconColor)
            )
    }
}

/// 白底胶囊按钮（发音 / 慢速 / 添加笔记 / 笔记专区 / 编辑词义 …）
struct PillButton<Label: View>: View {
    var action: () -> Void = {}
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                label
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(AppTheme.ink2)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Capsule().fill(AppTheme.card).shadow(color: .black.opacity(0.06), y: 1, blur: 2))
        }
        .buttonStyle(.plain)
    }
}

/// 绿色小 tag（释义 / 接续 / 解释 / 名词 / 日文 / 中文 / 判断 …）
struct TagPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13.5, weight: .bold))
            .foregroundColor(AppTheme.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(AppTheme.primarySoft))
    }
}

/// 例句级别徽章（N3 黄色 / N5 绿色，与设计稿一致）
struct LevelBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13.5, weight: .heavy))
            .foregroundColor(AppTheme.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(AppTheme.primarySoft))
    }
}

/// 词本封面小方块（首页 Hero / 词本列表卡），badge 文字取 books.json badge
struct BookCoverTile: View {
    let badge: String
    let tint: Int
    var size: CGSize = CGSize(width: 46, height: 46)

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: size.height * 0.26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.coverColor(tint: tint).opacity(0.9), AppTheme.coverColor(tint: tint)],
                        startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1)
                    )
                )
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 2)
                .padding(.leading, 7)
        }
        .overlay(
            Text(badge)
                .font(.system(size: size.height * 0.32, weight: .heavy))
                .foregroundColor(.white)
                .padding(.leading, 10)
            , alignment: .center
        )
        .frame(width: size.width, height: size.height)
        .shadow(color: .black.opacity(0.15), y: 3, blur: 8)
    }
}

/// 细进度条（track + 墨绿填充）
struct HairlineProgressBar: View {
    var progress: Double   // 0...1
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.track)
                Capsule()
                    .fill(LinearGradient(colors: [AppTheme.primaryPressed, AppTheme.primary],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(3, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Color(hex:)

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
