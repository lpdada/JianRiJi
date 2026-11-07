import SwiftUI
import Vision
import UIKit

/// 手写输入：看中文意思，在画布上写出日文词形，用 Vision 识别并判分。
/// 只处理内存里的 UIImage，不用相机、不拍照、不存图。
///
/// 修了四处：
///  1. **画布写死 320×320**。iPhone SE（320pt 宽）减去左右 16pt padding 只剩 288pt，
///     画布会横向溢出。改成按可用宽度自适应，最大 340。
///  2. **只取识别结果的第一个候选**。手写假名常被认成形近字，取 `topCandidates(3)`，
///     任一命中就算对。
///  3. **完全认不出来也按「错」处理并扣记忆分**。识别为空意味着「机器没看懂」，
///     不是「你写错了」——这时不判分，让用户擦掉重写。
///  4. 每次切词都 `scopedWords.shuffled()`（10660 词全量重排），改成维护一个 pool。
struct HandwritingView: View {
    @EnvironmentObject private var store: Store

    @State private var pool: [Word] = []
    @State private var target: Word?
    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var recognized: String?
    @State private var verdict: Verdict = .idle
    @State private var correct = 0
    @State private var total = 0
    @State private var recognizing = false
    @State private var canvasSide: CGFloat = 320

    enum Verdict { case idle, right, wrong, unreadable }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                scoreBar
                promptCard
                canvasCard
                actionRow
                feedback
                footer
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(AppTheme.bgMint.ignoresSafeArea())
        .navigationTitle("手写")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if target == nil { next() }
        }
    }

    private var scoreBar: some View {
        HStack {
            Text(total == 0 ? "还没开始" : "\(correct) / \(total) 正确")
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
            Spacer()
            Button {
                if let word = target {
                    Speech.shared.speak(word.reading, rate: store.settings.speechRate)
                }
            } label: {
                Label("听读音", systemImage: "speaker.wave.2.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.primary)
        }
    }

    private var promptCard: some View {
        VStack(spacing: 6) {
            Text("写出下面这个词")
                .font(.footnote)
                .foregroundStyle(AppTheme.ink3)
            Text(target?.meaning ?? "—")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.ink)
            Text("写词形也可以，写假名读音也可以")
                .font(.caption2)
                .foregroundStyle(AppTheme.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.card)
        )
    }

    private var canvasCard: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let side = max(200, geo.size.width)
                Canvas { context, _ in
                    for stroke in strokes + (currentStroke.isEmpty ? [] : [currentStroke]) {
                        context.stroke(path(for: stroke), with: .color(.black), lineWidth: 5)
                    }
                }
                .frame(width: side, height: side)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AppTheme.hairline, lineWidth: 1)
                )
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard verdict == .idle || verdict == .unreadable else { return }
                            currentStroke.append(value.location)
                        }
                        .onEnded { _ in
                            if !currentStroke.isEmpty {
                                strokes.append(currentStroke)
                                currentStroke = []
                            }
                        }
                )
                .onAppear { canvasSide = side }
                .onChange(of: side) { canvasSide = $0 }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 340)

            HStack(spacing: 10) {
                Button {
                    strokes = []
                    currentStroke = []
                    recognized = nil
                    verdict = .idle
                } label: {
                    Text("擦掉重写")
                }
                .buttonStyle(GhostButtonStyle(tint: AppTheme.ink3))
                Spacer()
                Text("写完点「识别判分」")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.ink3)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.card)
        )
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                recognize()
            } label: {
                Text(recognizing ? "识别中…" : "识别判分")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(strokes.isEmpty || recognizing || verdict == .right || verdict == .wrong)

            Button {
                next()
            } label: {
                Text("下一词")
            }
            .buttonStyle(GhostButtonStyle(tint: AppTheme.primary))
        }
    }

    @ViewBuilder
    private var feedback: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch verdict {
            case .idle:
                EmptyView()

            case .right:
                Text("对了：\(target?.term ?? "")  ·  \(target?.reading ?? "")")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.success)

            case .unreadable:
                Text("没认出你写的字。擦掉重写一次，字写得大一点会更准。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.warning)
                Text("这一次不计分、不动记忆进度。")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.ink3)

            case .wrong:
                Text("识别成「\(recognized ?? "")」，正确答案：\(target?.term ?? "")  ·  \(target?.reading ?? "")")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.danger)
                Text("手写识别认的是字形，写得潦草、笔画连在一起都可能认错；这一次不计入记忆进度。")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        Text("手写答对会按「记得」推进记忆进度；认错或写错只提示，不扣分。")
            .font(.caption2)
            .foregroundStyle(AppTheme.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 绘制

    private func path(for stroke: [CGPoint]) -> Path {
        var path = Path()
        guard let first = stroke.first else { return path }
        if stroke.count == 1 {
            path.addEllipse(in: CGRect(x: first.x - 2.5, y: first.y - 2.5, width: 5, height: 5))
            return path
        }
        path.move(to: first)
        for point in stroke.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    /// 把笔画渲染成内存里的 UIImage，不落盘、不走相机。
    private func renderImage() -> UIImage? {
        let side = max(200, canvasSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            UIColor.black.setStroke()
            let cg = context.cgContext
            cg.setLineWidth(10)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for stroke in strokes {
                guard let first = stroke.first else { continue }
                cg.beginPath()
                cg.move(to: first)
                for point in stroke.dropFirst() {
                    cg.addLine(to: point)
                }
                if stroke.count == 1 {
                    cg.addEllipse(in: CGRect(x: first.x - 5, y: first.y - 5, width: 10, height: 10))
                }
                cg.strokePath()
            }
        }
    }

    // MARK: - 识别

    private func recognize() {
        guard let word = target,
              verdict != .right, verdict != .wrong,
              !strokes.isEmpty,
              let image = renderImage(),
              let cgImage = image.cgImage else { return }

        recognizing = true
        recognized = nil

        let request = VNRecognizeTextRequest { request, _ in
            // 取前 3 个候选：手写假名常被认成形近字，只取第一个太苛刻。
            let candidates = (request.results ?? [])
                .compactMap { $0 as? VNRecognizedTextObservation }
                .flatMap { observation in
                    observation.topCandidates(3).map(\.string)
                }
            DispatchQueue.main.async {
                self.recognizing = false
                self.finishRecognized(candidates, for: word)
            }
        }
        request.recognitionLanguages = ["ja-JP"]
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    private func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{3000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finishRecognized(_ candidates: [String], for word: Word) {
        let cleaned = candidates.map(clean).filter { !$0.isEmpty }
        recognized = cleaned.first

        // 一个都没认出来：机器没看懂，不是用户写错。不判分。
        guard !cleaned.isEmpty else {
            verdict = .unreadable
            return
        }

        let isRight = cleaned.contains { text in
            if text == word.term || text == word.reading { return true }
            // 多字词允许「识别结果里含目标词」（连笔多写一笔的情况）。
            if word.term.count >= 2, text.contains(word.term) { return true }
            // 也允许读假名时多认了一个假名。
            if word.reading.count >= 2, text.contains(word.reading) { return true }
            return false
        }

        if isRight {
            total += 1
            correct += 1
            store.grade(word: word, grade: .good)
            verdict = .right
        } else {
            // 写错/认错都不写 SRS：手写是输出训练，不该反过来惩罚记忆状态。
            verdict = .wrong
        }
    }

    private func next() {
        if pool.isEmpty {
            pool = store.scopedWords.shuffled()
        }
        target = pool.popLast()
        strokes = []
        currentStroke = []
        recognized = nil
        verdict = .idle
        recognizing = false
        // 故意不在切词时自动朗读：这题是看中文意思写词形，自动读读音等于直接给答案。
        // 想听读音点右上角「听读音」，那是自愿要的提示。
    }
}
