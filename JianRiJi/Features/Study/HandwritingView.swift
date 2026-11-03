import SwiftUI
import Vision
import UIKit

/// 手写输入：看中文意思，在画布上写出日文词形，用 Vision 识别并判分。
/// 只处理内存里的 UIImage，不用相机、不拍照、不存图。
/// 识别用 Vision VNRecognizeTextRequest，日语 ja-JP、accurate 级别。
struct HandwritingView: View {
    @EnvironmentObject private var store: Store

    @State private var target: Word?
    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var recognized: String?
    @State private var verdict: Verdict = .idle
    @State private var correct = 0
    @State private var total = 0
    @State private var recognizing = false

    enum Verdict { case idle, right, wrong }

    /// 画布固定尺寸，渲染识别图时用同一尺寸，避免坐标换算出错。
    private let canvasSize = CGSize(width: 320, height: 320)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                scoreBar
                promptCard
                canvasCard
                actionRow
                if verdict != .idle { feedback }
                footer
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Theme.paper.ignoresSafeArea())
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
                .foregroundStyle(Theme.muted)
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
            .foregroundStyle(Theme.accent)
        }
    }

    private var promptCard: some View {
        VStack(spacing: 6) {
            Text("写出下面这个词")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            Text(target?.meaning ?? "—")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("写词形也可以，写假名读音也可以")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .paperCard(padding: 16)
    }

    private var canvasCard: some View {
        VStack(spacing: 10) {
            Canvas { context, _ in
                for stroke in strokes + (currentStroke.isEmpty ? [] : [currentStroke]) {
                    context.stroke(path(for: stroke), with: .color(.primary), lineWidth: 5)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        currentStroke.append(value.location)
                    }
                    .onEnded { _ in
                        if !currentStroke.isEmpty {
                            strokes.append(currentStroke)
                            currentStroke = []
                        }
                    }
            )

            HStack(spacing: 10) {
                Button {
                    strokes = []
                    currentStroke = []
                    recognized = nil
                    verdict = .idle
                } label: {
                    Text("擦掉重写")
                }
                .buttonStyle(GhostButtonStyle(tint: Theme.muted))
                Spacer()
                Text("写完点「识别判分」")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
        }
        .paperCard(padding: 14)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                recognize()
            } label: {
                Text(recognizing ? "识别中…" : "识别判分")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(strokes.isEmpty || recognizing || verdict != .idle)

            Button {
                next()
            } label: {
                Text("下一词")
            }
            .buttonStyle(GhostButtonStyle(tint: Theme.accent))
        }
    }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 8) {
            if verdict == .right {
                Text("对了：\(target?.term ?? "")  ·  \(target?.reading ?? "")")
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
            } else {
                Text("识别成「\(recognized ?? "")」，正确答案：\(target?.term ?? "")  ·  \(target?.reading ?? "")")
                    .font(.footnote)
                    .foregroundStyle(Color(red: 0.78, green: 0.32, blue: 0.28))
            }
            Text("手写识别认的是字形，写得潦草、笔画连在一起都可能认错，认错不代表你没记住。")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        Text("手写会推进记忆进度：识别对按「记得」，识别错按「忘了」。")
            .font(.caption2)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 逻辑

    private func path(for stroke: [CGPoint]) -> Path {
        var path = Path()
        guard let first = stroke.first else { return path }
        if stroke.count == 1 {
            // 单点一笔：画个小圆，不然 Canvas 里看不见。
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
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))
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

    private func recognize() {
        guard let word = target, verdict == .idle, !strokes.isEmpty,
              let image = renderImage(), let cgImage = image.cgImage else { return }
        recognizing = true
        recognized = nil

        let request = VNRecognizeTextRequest { request, _ in
            let text = request.results?
                .compactMap { $0 as? VNRecognizedTextObservation }
                .compactMap { $0.topCandidates(1).first?.string }
                .joined()
                ?? ""
            DispatchQueue.main.async {
                self.recognizing = false
                self.finishRecognized(text, for: word)
            }
        }
        request.recognitionLanguages = ["ja-JP"]
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    private func finishRecognized(_ raw: String, for word: Word) {
        let cleaned = raw
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        recognized = cleaned
        // 词形和读音都算对：写汉字词形对，写假名读音也对。
        let isRight = !cleaned.isEmpty && (cleaned == word.term || cleaned == word.reading)
        verdict = isRight ? .right : .wrong
        total += 1
        if isRight { correct += 1 }
        store.grade(word: word, grade: isRight ? .good : .again)
    }

    private func next() {
        let pool = store.scopedWords.shuffled()
        target = pool.first
        strokes = []
        currentStroke = []
        recognized = nil
        verdict = .idle
        recognizing = false
        // 故意不在切词时自动朗读：这题是看中文意思写词形，自动读读音等于直接给答案。
        // 想听读音点右上角「听读音」，那是自愿要的提示。
    }
}
