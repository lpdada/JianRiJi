//  AppTheme.swift
//  简日记 · 设计 tokens & 通用小组件
//
//  2024-11 改版引入了这套新 token，但当时所有颜色都是写死的十六进制值：
//  `AppTheme.card = .white`、`AppTheme.bgMint = 0xE9F2EE`。
//  结果是**新界面完全没有暗色模式**——首页、词本、学习页在夜间模式下依旧一片浅绿白，
//  而同期的旧界面（ReviewView 等，走 Theme.swift 的动态色）却能正常变暗。
//  一个 App 里两种夜间行为，是用户最容易察觉的「不专业」。
//
//  这里把每个 token 改成 light/dark 双值动态色，**API 名字全部保持不变**，
//  调用方一行都不用改，全局获得暗色支持。

import SwiftUI
import UIKit

// MARK: - 设计 tokens

enum AppTheme {

    /// 页面渐变浅景底（首页 / 词本 / 学习页背景）
    static let bgTop = dynamic(0xE7EFE9, 0x0F1513)
    static let bgBottom = dynamic(0xEEF2EE, 0x131A17)
    static var screenGradient: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: UnitPoint(x: 0.25, y: 1))
    }
    /// 洗脑 / 学习页底部纯色底
    static let bgMint = dynamic(0xE9F2EE, 0x121A17)

    /// 墨绿主色（按钮、选中 chip、大字词条、下划线强调）
    /// 暗色下必须提亮：0x0E6B5A 放在 0x121A17 上几乎看不见。
    static let primary = dynamic(0x0E6B5A, 0x4FC7A8)
    static let primaryDeep = dynamic(0x0C5F50, 0x3FB89A)
    static let primaryPressed = dynamic(0x137A66, 0x5FD4B6)
    /// 淡绿底（图标圆底、tag pill、选中 tab 背景）
    static let primarySoft = dynamic(0xDFECE6, 0x1C2A25)
    static let primarySoftStroke = dynamic(0xCFE3DA, 0x27352F)

    /// 文字三档
    static let ink = dynamic(0x1F2A26, 0xE8EFEB)
    static let ink2 = dynamic(0x57685F, 0xA8B8B1)
    static let ink3 = dynamic(0x93A49B, 0x7C8C85)

    /// 卡片与进度条
    static let card = dynamic(0xFFFFFF, 0x1A2220)
    static let track = dynamic(0xE3EBE6, 0x24302B)
    static let hairline = dynamic(0xE7ECE9, 0x2A3531)

    /// 语义色。评分、对错、提示都用它们，别在 View 里再写 Color(red:green:blue:)。
    static let danger = dynamic(0xC75240, 0xE0715F)
    static let warning = dynamic(0xB88534, 0xD9A64A)
    static let success = dynamic(0x3D9E78, 0x4FC7A8)

    static let cardRadius: CGFloat = 20
    static let heroRadius: CGFloat = 20
    static let tileRadius: CGFloat = 18

    /// 圆角阴影：暗色下阴影几乎不可见，改用描边（见 `cardShadow`）。
    static func cardShadow(_ radius: CGFloat = 12, opacity: Double = 0.05, y: CGFloat = 4) -> Color {
        Color.black.opacity(opacity)
    }

    // MARK: 动态色

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

// MARK: - 词本封面色（books.json 里 tint: 0~3）

extension AppTheme {
    static func coverColor(tint: Int) -> Color {
        switch tint {
        case 0: return dynamic(0x3E8E7E, 0x2E6E62)  // 全部词本 · 青绿
        case 1: return dynamic(0xD8956B, 0xA87254)  // 初级 · 杏
        case 2: return dynamic(0xE0564F, 0xAB4640)  // JLPT/考试 · 红
        case 3: return dynamic(0x5B9BD5, 0x477BA8)  // 高级/测试 · 蓝
        default: return dynamic(0x3E8E7E, 0x2E6E62)
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
            .background(
                Capsule()
                    .fill(AppTheme.card)
                    .shadow(color: AppTheme.cardShadow(2, opacity: 0.06, y: 1), radius: 2, x: 0, y: 1)
            )
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
                        colors: [
                            AppTheme.coverColor(tint: tint).opacity(0.9),
                            AppTheme.coverColor(tint: tint),
                        ],
                        startPoint: UnitPoint(x: 0.2, y: 0),
                        endPoint: UnitPoint(x: 0.8, y: 1)
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
                .padding(.leading, 10),
            alignment: .center
        )
        .frame(width: size.width, height: size.height)
        .shadow(color: AppTheme.cardShadow(8, opacity: 0.15, y: 3), radius: 8, x: 0, y: 3)
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
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.primaryPressed, AppTheme.primary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
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

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
