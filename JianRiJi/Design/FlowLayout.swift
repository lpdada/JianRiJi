import SwiftUI

/// 简单流式布局：子视图按行排列，行满换行。iOS 16 的 Layout 协议即可，不用 iOS 17+ API。
/// 经典模式的注音例句用它按段换行，每段是一列（读音 / 词形 / romaji 三行）。
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = layoutRows(proposal: proposal, subviews: subviews)
        let width = proposal.width ?? rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in layoutRows(proposal: proposal, subviews: subviews) {
            var x = bounds.minX
            for (index, size) in row.items {
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layoutRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : current.width + horizontalSpacing + size.width
            if !current.items.isEmpty, needed > maxWidth {
                rows.append(current)
                current = Row()
            }
            if !current.items.isEmpty {
                current.width += horizontalSpacing
            }
            current.items.append((index, size))
            current.width += size.width
            current.height = max(current.height, size.height)
        }
        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
