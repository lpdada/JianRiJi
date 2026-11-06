import AVFoundation
import Foundation

/// 朗读控制器：单句朗读 + 「洗脑」循环（读 N 遍，可暂停 / 可停）。
///
/// 为什么不用 `Speech` 直接循环：`Speech.swift` 里的 `speak` 是"发出去就不管了"，
/// 没有播完回调，循环只能按字数估算等待，长句要么被截断、要么空等。
/// 这里自己拿 `AVSpeechSynthesizerDelegate` 的 didFinish，读完一句再读下一句。
///
/// 两套 synthesizer（Speech 和这里）不会同时发声：经典模式统一只用这个，
/// 词条详情的「读一遍」用 `Speech`，两者不在同一个界面同时用。
@MainActor
final class SpeechLoop: NSObject, ObservableObject {

    enum Phase: Equatable {
        case idle
        case speaking
        case paused
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var completedRounds = 0
    @Published private(set) var totalRounds = 0

    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "ja-JP")
    private var pending: CheckedContinuation<Void, Never>?
    private var runTask: Task<Void, Never>?
    private var rate: Double = 0.45

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isRunning: Bool { phase != .idle }
    var isPaused: Bool { phase == .paused }

    /// 还剩几遍没读（界面上「剩余次数」用它）。
    var remainingRounds: Int {
        max(0, totalRounds - completedRounds)
    }

    // MARK: - 对外接口

    /// 读一句，读完就结束。
    func speak(_ text: String, rate: Double) {
        stopLoop()
        self.rate = rate
        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.speakOnce(text)
            self.runTask = nil
        }
    }

    /// 循环朗读：每遍按顺序读 `lines` 里的每一句，一共 `rounds` 遍。
    func startLoop(_ lines: [String], rounds: Int, rate: Double) {
        stopLoop()
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty, rounds > 0 else { return }

        self.rate = rate
        totalRounds = rounds
        completedRounds = 0
        phase = .speaking

        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for round in 0..<rounds {
                if Task.isCancelled { break }
                await self.waitWhilePaused()
                if Task.isCancelled || self.phase == .idle { break }

                for line in cleaned {
                    if Task.isCancelled { break }
                    await self.waitWhilePaused()
                    if Task.isCancelled || self.phase == .idle { break }
                    await self.speakOnce(line)
                }

                if self.phase == .idle { break }
                self.completedRounds = round + 1
            }
            if !Task.isCancelled {
                self.phase = .idle
            }
            self.runTask = nil
        }
    }

    /// 洗脑按钮：读的时候点一下暂停，暂停时点一下继续。
    func togglePause() {
        switch phase {
        case .speaking:
            phase = .paused
            synthesizer.stopSpeaking(at: .immediate)
        case .paused:
            phase = .speaking
        case .idle:
            break
        }
    }

    func stopLoop() {
        runTask?.cancel()
        runTask = nil
        phase = .idle
        synthesizer.stopSpeaking(at: .immediate)
        finishCurrent()
    }

    // MARK: - 内部

    private func waitWhilePaused() async {
        while phase == .paused && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
    }

    private func speakOnce(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Speech.shared.activateSession()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.rate = Float(min(max(rate, 0.30), 0.60))
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pending = continuation
            synthesizer.speak(utterance)

            // 系统 TTS 偶尔不给 didFinish（切后台、语音包异常）。
            // 兜一个上限，宁可少等一拍，也不能让整个循环永久挂在这里。
            let seconds = min(20.0, Double(trimmed.count) * 0.45 + 3.0)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                self?.finishCurrent()
            }
        }
    }

    /// 幂等：多个来源（didFinish / didCancel / 兜底超时）都会调，只放行一次。
    private func finishCurrent() {
        guard let continuation = pending else { return }
        pending = nil
        continuation.resume()
    }
}

extension SpeechLoop: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.finishCurrent() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.finishCurrent() }
    }
}
