import SwiftUI
import UIKit

/// 一套很克制的中日混排配色：朱红做强调，纸色做底，留白给呼吸。
enum Theme {
    static let accent = Color(red: 0.80, green: 0.29, blue: 0.22)
    static let jade = Color(red: 0.13, green: 0.45, blue: 0.40)
    static let indigo = Color(red: 0.24, green: 0.32, blue: 0.58)

    static let paper = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
            : UIColor(red: 0.976, green: 0.969, blue: 0.953, alpha: 1)
    })

    static let card = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.13, green: 0.13, blue: 0.145, alpha: 1)
            : UIColor.white
    })

    static let muted = Color(uiColor: .secondaryLabel)
    static let hairline = Color(uiColor: .separator)
}

struct PaperCard: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func paperCard(padding: CGFloat = 16) -> some View {
        modifier(PaperCard(padding: padding))
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
