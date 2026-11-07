import SwiftUI

/// 语音设置。
///
/// 两条路，都不花钱：
/// 1. **系统语音**：同一台设备可能同时装着默认档和增强档，选增强/高级立刻不一样；
/// 2. **语音包**：用 `tools/voice/gen_pack.py`（edge-tts，免费、无需 Key）批量生成
///    `ja-JP-NanamiNeural` 的词读音，装进 App 后完全离线播放。
///
/// 没有录音、也没有按次计费的云服务：前者你不想要，后者要花钱。
struct VoiceSettingsView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @StateObject private var packs = VoicePackStore()

    @State private var voices: [VoiceOption] = []
    @State private var selectedID: String?
    @State private var endpointDraft = ""
    @State private var showClearConfirm = false

    private let sampleText = "こんばんは。今日はいい声が出ていますか。"

    var body: some View {
        NavigationStack {
            Form {
                systemVoiceSection
                packSection
                installedSection
                librarySection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("语音")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear(perform: refresh)
            .confirmationDialog("清空全部真人音频？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    VoicePack.removeAll()
                    for id in VoicePackInstaller.installedPackIDs() {
                        VoicePackInstaller.uninstall(packID: id)
                    }
                    packs.refreshInstalled()
                }
                Button("算了", role: .cancel) {}
            } message: {
                Text("装过的语音包会变成未安装状态，之后可以重新下载。")
            }
        }
    }

    private func refresh() {
        voices = VoiceCatalog.japaneseVoices()
        selectedID = VoiceCatalog.current()?.id
        endpointDraft = packs.endpoint
        packs.refreshInstalled()
    }

    // MARK: - 系统语音

    private var systemVoiceSection: some View {
        Section {
            if voices.isEmpty {
                Text("系统里一个日语语音都没装。去「设置 → 辅助功能 → 朗读内容 → 声音 → 日语」下载一个。")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(voices) { option in
                    Button {
                        VoiceCatalog.select(option)
                        selectedID = option.id
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.name)
                                    .foregroundStyle(Color.primary)
                                HStack(spacing: 6) {
                                    Text("音质 \(option.qualityLabel)")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .foregroundStyle(option.isHighQuality ? Theme.accent : Theme.muted)
                                        .background(
                                            (option.isHighQuality ? Theme.accent : Theme.muted).opacity(0.12),
                                            in: Capsule()
                                        )
                                    Text(option.id)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.muted)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if selectedID == option.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Speech.shared.speak(sampleText, rate: store.settings.speechRate)
                } label: {
                    Label("试听当前语音", systemImage: "waveform")
                }
            }
        } header: {
            Text("系统语音")
        } footer: {
            if VoiceCatalog.isUsingCompactVoice {
                Text("现在用的是「默认」音质，也是听着最机械的那一档。去「设置 → 辅助功能 → 朗读内容 → 声音 → 日语」下载「增强」或「高级」语音，回来选中它，会明显自然很多——文件几十 MB，一次性下载，之后离线可用。")
            } else {
                Text("已经用上更高质量的语音。没有语音包时就用它，不联网。")
            }
        }
    }

    // MARK: - 语音包

    private var packSection: some View {
        Section {
            TextField("语音包地址，如 https://example.com/voice", text: $endpointDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.URL)

            Button {
                packs.endpoint = endpointDraft
                Task { await packs.loadCatalog() }
            } label: {
                Label("读取目录", systemImage: "arrow.clockwise")
            }

            if !packs.catalog.isEmpty {
                ForEach(packs.catalog) { pack in
                    packRow(pack)
                }
            }

            if let error = packs.errorText {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.78, green: 0.32, blue: 0.28))
            }

            if let status = packs.status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        } header: {
            Text("语音包（免费 · 离线）")
        } footer: {
            Text("用仓库里的 `tools/voice/gen_pack.py` 生成：它会调 edge-tts（微软 Edge 的朗读接口，免费、不需要 Key）批量生成 ja-JP-NanamiNeural 的词读音，产出一个 catalog.json 和若干 .voicepack。把这两个东西放到任意能访问的地址（自己的服务器、网盘直链都行），上面的地址填那个目录即可。装好之后朗读优先用包里的录音，完全离线。")
        }
    }

    @ViewBuilder
    private func packRow(_ pack: RemoteVoicePack) -> some View {
        let isInstalled = packs.installed.contains(pack.id)
        let isBusy = packs.busyPackID == pack.id

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.title)
                        .foregroundStyle(Color.primary)
                    Text("\(pack.count) 条 · \(ByteCountFormatter.string(fromByteCount: pack.bytes, countStyle: .file))")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()

                if isBusy {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if isInstalled {
                    Button("卸载") {
                        packs.uninstall(packID: pack.id)
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                } else {
                    Button("安装") {
                        Task { await packs.install(pack) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .disabled(packs.busyPackID != nil)
                }
            }

            if isBusy {
                ProgressView(value: packs.progress)
                    .tint(Theme.accent)
            }

            if isInstalled, let count = packs.installedCounts[pack.id] {
                Text("已安装 \(count) 条")
                    .font(.caption2)
                    .foregroundStyle(Theme.jade)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 已安装

    private var installedSection: some View {
        Section {
            if packs.installed.isEmpty {
                Text("还没有装语音包。")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(Array(packs.installed).sorted(), id: \.self) { id in
                    HStack {
                        Text(id.uppercased())
                        Spacer()
                        Text("\(packs.installedCounts[id] ?? 0) 条")
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        } header: {
            Text("已安装")
        }
    }

    // MARK: - 库

    private var librarySection: some View {
        Section {
            HStack {
                Text("本地音频文件")
                Spacer()
                Text("\(VoicePack.wordAudioCount()) 条")
                    .foregroundStyle(Theme.muted)
            }
            HStack {
                Text("占用空间")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: VoicePack.totalBytes(), countStyle: .file))
                    .foregroundStyle(Theme.muted)
            }
            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Text("清空全部本地音频")
            }
        } header: {
            Text("本地音频库")
        } footer: {
            Text("这些文件只在本机，不进学习存档，也不会传给任何服务器。")
        }
    }
}
