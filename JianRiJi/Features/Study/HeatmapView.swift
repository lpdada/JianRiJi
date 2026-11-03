import SwiftUI

/// 打卡热力图：把 Store.log 按自然日聚合，画最近 12 周（7 行 × 12 列）。
/// 纯 SwiftUI，不引图表库。颜色是 Theme.accent 的透明度阶梯，今天那格加描边。
/// 数据只依赖 [ReviewLogEntry]，不直接依赖 Store，方便以后换数据源。
struct HeatmapView: View {
    let log: [ReviewLogEntry]

    private let calendar = Calendar.current
    private let weeks = 12
    private let daysPerWeek = 7

    /// 最近 12 周的第一天：按设备日历的周起始对齐，保证每列都是完整的一周。
    private var startDay: Date {
        let today = calendar.startOfDay(for: Date())
        let elevenWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: today) ?? today
        return calendar.dateInterval(of: .weekOfYear, for: elevenWeeksAgo)?.start ?? elevenWeeksAgo
    }

    /// 按自然日聚合的次数表，key 是当天的 0 点。
    private var countsByDay: [Date: Int] {
        var result: [Date: Int] = [:]
        for entry in log {
            let day = calendar.startOfDay(for: entry.at)
            result[day, default: 0] += 1
        }
        return result
    }

    private var totalInWindow: Int {
        let start = startDay
        let end = calendar.date(byAdding: .day, value: weeks * daysPerWeek, to: start) ?? Date()
        return log.filter { $0.at >= start && $0.at < end }.count
    }

    /// 84 天的格子，按「行优先、列是周」排给 LazyVGrid：
    /// 第 0 行是 12 周各自的第 1 天，第 1 行是各自的第 2 天……这样 12 列正好是 12 周。
    private var cells: [(day: Date, count: Int, isToday: Bool)] {
        let today = calendar.startOfDay(for: Date())
        var result: [(Date, Int, Bool)] = []
        for row in 0..<daysPerWeek {
            for column in 0..<weeks {
                let offset = column * daysPerWeek + row
                let day = calendar.date(byAdding: .day, value: offset, to: startDay) ?? startDay
                result.append((day, countsByDay[day] ?? 0, day == today))
            }
        }
        return result
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 3), count: weeks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("打卡热力图")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("最近 12 周 · \(totalInWindow) 次")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            if log.isEmpty {
                Text("还没有复习记录，练一张卡，这里就亮一格。")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            } else {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color(for: cell.count))
                            .frame(height: 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(
                                        cell.isToday ? Theme.accent : Color.clear,
                                        lineWidth: cell.isToday ? 1.5 : 0
                                    )
                            )
                    }
                }

                HStack(spacing: 4) {
                    Text("少")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                    ForEach([0, 1, 3, 6, 10], id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(color(for: level))
                            .frame(width: 10, height: 10)
                    }
                    Text("多")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text("描边的是今天")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .paperCard(padding: 16)
    }

    private func color(for count: Int) -> Color {
        switch count {
        case 0: return Color.primary.opacity(0.07)
        case 1...2: return Theme.accent.opacity(0.25)
        case 3...5: return Theme.accent.opacity(0.5)
        case 6...9: return Theme.accent.opacity(0.75)
        default: return Theme.accent
        }
    }
}
