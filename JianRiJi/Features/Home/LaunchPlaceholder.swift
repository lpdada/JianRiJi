import SwiftUI

/// 首帧占位：词库还在后台解析时显示，避免出现「0 个词」的假数据。
struct LaunchPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("正在载入词库…")
                .font(.footnote)
                .foregroundStyle(AppTheme.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.bgMint)
    }
}
