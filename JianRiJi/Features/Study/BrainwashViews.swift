//  BrainwashViews.swift
//  洗脑模块 —— ①全屏循环朗读 overlay ②独立设置页 ③配置存储
//  对应设计稿: study-and-brainwash.png ④⑤
//
//  关键语义（与现有 app 一致）：
//   · "洗脑中，第 X 拍，按拍念" —— 洗脑是循环朗读，不是学习，不写 reviewLog
//   · "循环听，不动手"（随身听同理，只连播）
//   · 朗读链路：语音包 → 服务器合成(Nanami) → 系统语音（保持现有 fallback，不改）
//
//  驱动方式：overlay 直接用现有的 SpeechLoop.startLoop 驱动（不是自写 Task +
//  固定 sleep 估算）；剩余次数取 loop.remainingRounds，点屏退出调 stopLoop，
//  词速/句速各走各的 rate（SpeechLine 自带 Optional rate）。

import SwiftUI
import Combine

// MARK: - 配置（独立设置，App 各处共用）
//
// 键名固定：bw.autoPlaySentence / bw.wordRate / bw.sentenceRate / bw.repeatCount。
// 用 @Published + UserDefaults（不用 @AppStorage 藏进 ObservableObject 里，
// 那样视图收不到变更通知）。

final class BrainwashStore: ObservableObject {
    @Published var autoPlaySentence: Bool {
        didSet { UserDefaults.standard.set(autoPlaySentence, forKey: "bw.autoPlaySentence") }
    }
    @Published var wordRate: Float {
        didSet { UserDefaults.standard.set(wordRate, forKey: "bw.wordRate") }
    }
    @Published var sentenceRate: Float {
        didSet { UserDefaults.standard.set(sentenceRate, forKey: "bw.sentenceRate") }
    }
    @Published var repeatCount: Int {
        didSet { UserDefaults.standard.set(repeatCount, forKey: "bw.repeatCount") }
    }

    init() {
        let defaults = UserDefaults.standard
        autoPlaySentence = defaults.object(forKey: "bw.autoPlaySentence") as? Bool ?? true
        wordRate = defaults.object(forKey: "bw.wordRate") as? Float ?? 1.0
        sentenceRate = defaults.object(forKey: "bw.sentenceRate") as? Float ?? 1.0
        repeatCount = defaults.object(forKey: "bw.repeatCount") as? Int ?? 10
    }
}

// MARK: - 全屏洗脑 overlay（词卡点「洗脑」进入）

struct BrainwashOverlayView: View {
    @ObservedObject var config: BrainwashStore
    @ObservedObject var loop: SpeechLoop

    let wordText: String      // 当前词（读音）
    let sentenceText: String  // 例句
    let wordAudioKey: String?
    let sentenceAudioKey: String?
    var onExit: () -> Void = {}

    @State private var started = false
    @State private var exited = false
    @State private var showSettings = false
    @State private var wasSpeakingBeforeSettings = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(spacing: 0) {
                // 循环呼吸动画的「洗脑脸」
                LoopFace()
                    .frame(width: 130, height: 100)
                    .modifier(Breathing())
                    .padding(.top, 250)
                Text("洗脑中...")
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.top, 18)
                HStack(spacing: 6) {
                    Text("剩余次数：")
                        .font(.system(size: 17)).foregroundColor(Color(hex: 0xE7EFEB))
                    Text("\(loop.remainingRounds)")
                        .font(.system(size: 22, weight: .heavy)).foregroundColor(.white)
                        .monospacedDigit()
                }
                .padding(.top, 12)
                Text("点击屏幕任意地方即可退出")
                    .font(.system(size: 15.5)).foregroundColor(Color(hex: 0xDFE9E3))
                    .padding(.top, 14)

                // 白色「设置」pill：用纯手势不用 Button，否则点它会同时触发
                // 外层点屏退出的手势；子视图的手势优先于父视图的同类手势。
                Text("设置")
                    .font(.system(size: 17.5, weight: .heavy))
                    .foregroundColor(AppTheme.primaryDeep)
                    .frame(width: 128, height: 56)
                    .background(Capsule().fill(Color.white).shadow(color: .black.opacity(0.25), y: 3, blur: 10))
                    .padding(.top, 26)
                    .onTapGesture { openSettings() }
            }
        }
        .onTapGesture { exit() }
        .onAppear { start() }
        .onDisappear { loop.stopLoop() }
        .onChange(of: loop.phase) { newPhase in
            // 自然读完：phase 回到 idle，自动退出。
            if newPhase == .idle, started, !exited {
                exit()
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: resumeAfterSettings) {
            BrainwashSettingsView()
        }
    }

    private func exit() {
        guard !exited else { return }
        exited = true
        loop.stopLoop()
        onExit()
    }

    /// 循环：每遍按顺序读词（词速）+ 例句（句速，自动播放句子开时），
    /// 次数剩 0 时 SpeechLoop 自己停，phase 回 idle 后自动退出。
    private func start() {
        guard !started else { return }
        started = true
        var lines = [SpeechLine(wordText, audioKey: wordAudioKey, rate: Double(config.wordRate))]
        if config.autoPlaySentence,
           !sentenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(SpeechLine(sentenceText, audioKey: sentenceAudioKey, rate: Double(config.sentenceRate)))
        }
        loop.startLoop(lines, rounds: max(1, config.repeatCount), rate: Double(config.wordRate))
    }

    private func openSettings() {
        wasSpeakingBeforeSettings = (loop.phase == .speaking)
        if loop.phase == .speaking { loop.togglePause() }
        showSettings = true
    }

    private func resumeAfterSettings() {
        if wasSpeakingBeforeSettings, loop.phase == .paused {
            loop.togglePause()
        }
    }
}

// MARK: - 循环脸 + 呼吸动画

struct LoopFace: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.white).frame(width: 74, height: 74)
                .offset(x: -28)
            Circle().fill(Color.white.opacity(0.92)).frame(width: 74, height: 74)
                .offset(x: 28)
            // 眯眼 + 微笑
            Path { p in
                p.move(to: CGPoint(x: 26, y: 46)); p.addQuadCurve(to: CGPoint(x: 58, y: 46), control: CGPoint(x: 42, y: 36))
                p.move(to: CGPoint(x: 66, y: 46)); p.addQuadCurve(to: CGPoint(x: 98, y: 46), control: CGPoint(x: 82, y: 36))
            }
            .stroke(AppTheme.primaryDeep, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            Path { p in
                p.move(to: CGPoint(x: 44, y: 60)); p.addQuadCurve(to: CGPoint(x: 80, y: 60), control: CGPoint(x: 62, y: 70))
            }
            .stroke(AppTheme.primaryDeep, style: StrokeStyle(lineWidth: 6, lineCap: .round))
        }
    }
}

struct Breathing: ViewModifier {
    @State private var scale: CGFloat = 1.0
    func body(content: Content) -> some View {
        content.scaleEffect(scale)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: scale)
            .onAppear { scale = 1.06 }
    }
}

// MARK: - 洗脑设置页（独立页面，也可从 overlay「设置」进入）

struct BrainwashSettingsView: View {
    @EnvironmentObject private var config: BrainwashStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold)).foregroundColor(AppTheme.ink)
                }
                Text("洗脑设置")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(AppTheme.ink)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                toggleRow("自动播放句子", isOn: $config.autoPlaySentence)
                valueRow("发音速度", value: rateLabel(config.wordRate)) {
                    config.wordRate = nextRate(config.wordRate)
                }
                valueRow("句子播放速度", value: rateLabel(config.sentenceRate)) {
                    config.sentenceRate = nextRate(config.sentenceRate)
                }
                valueRow("洗脑播放次数", value: "\(config.repeatCount) 次") {
                    config.repeatCount = nextCount(config.repeatCount)
                }
            }
            .overlay(Divider().overlay(AppTheme.hairline), alignment: .top)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb").font(.system(size: 16)).foregroundColor(Color(hex: 0x8B978F))
                Text("洗脑循环播放当前词和例句，不推进记忆进度；背词进度只由学习模式推进。")
                    .font(.system(size: 15)).foregroundColor(AppTheme.ink2).lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0xEEF4F0)))
            .padding(20)

            Spacer()
        }
        .background(AppTheme.screenGradient.ignoresSafeArea())
    }

    /// 发音速度轮换：0.75 → 1 → 1.5 → 2（回到 0.75）。
    private func nextRate(_ rate: Float) -> Float {
        switch rate {
        case 0.75: return 1.0
        case 1.0: return 1.5
        case 1.5: return 2.0
        default: return 0.75
        }
    }

    /// 洗脑播放次数轮换：5 → 10 → 20（没有 ∞，次数递减到 0 要能自动退出）。
    private func nextCount(_ count: Int) -> Int {
        switch count {
        case 5: return 10
        case 10: return 20
        default: return 5
        }
    }

    private func rateLabel(_ r: Float) -> String {
        if r == 1 { return "1 倍" }
        if r < 1 { return "慢速" }
        return String(format: "%g 倍", r)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 17.5)).foregroundColor(AppTheme.ink)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(AppTheme.primary)
        }
        .frame(height: 74)
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) { Divider().overlay(AppTheme.hairline) }
    }

    private func valueRow(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 17.5)).foregroundColor(AppTheme.ink)
                Spacer()
                HStack(spacing: 8) {
                    Text(value).font(.system(size: 16.5, weight: .semibold)).foregroundColor(Color(hex: 0x8B978F))
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: 0xB6C2BB))
                }
            }
            .frame(height: 74)
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider().overlay(AppTheme.hairline) }
    }
}
