import SwiftUI
import UIKit

/// 对齐识日的视觉基调：深绿主色 + 薄荷浅绿块 + 白纸底，几乎不用阴影。
enum Theme {
    /// 主绿（标题、进度、实心按钮）
    static let accent = Color(red: 0.055, green: 0.420, blue: 0.310)
    /// 次绿（次级强调、成功态）
    static let jade = Color(red: 0.239, green: 0.620, blue: 0.470)
    /// 中性标签（词性、JLPT）
    static let indigo = Color(red: 0.420, green: 0.478, blue: 0.451)

    /// 薄荷块（「点击查看词义」、五十音格）
    static let mint = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.18, blue: 0.15, alpha: 1)
            : UIColor(red: 0.847, green: 0.929, blue: 0.890, alpha: 1)
    })

    static let paper = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.06, green: 0.07, blue: 0.07, alpha: 1)
            : UIColor(red: 0.99, green: 0.99, blue: 0.98, alpha: 1)
    })

    static let card = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.13, blue: 0.13, alpha: 1)
            : UIColor.white
    })

    static let muted = Color(uiColor: .secondaryLabel)
    static let hairline = Color(uiColor: .separator)

    /// 词本封面配色，按索引轮转
    static let deckTints: [Color] = [
        Color(red: 0.94, green: 0.62, blue: 0.25),
        Color(red: 0.24, green: 0.36, blue: 0.65),
        Color(red: 0.35, green: 0.63, blue: 0.38),
        Color(red: 0.85, green: 0.40, blue: 0.32)
    ]
}

struct PaperCard: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func paperCard(padding: CGFloat = 16, radius: CGFloat = 16) -> some View {
        modifier(PaperCard(padding: padding, radius: radius))
    }
}

enum DateText {
    static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "E"
        return f
    }()

    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日"
        return f
    }()
}
