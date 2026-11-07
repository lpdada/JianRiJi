# 语音改造：免费方案（无录音 · 无付费 API）

> 前置：`docs/MUSE_PROMPT.md`（硬约束）、`docs/MUSE_PROMPT_CLASSIC_V2.md`（经典模式 v2）
> 本次目标：朗读不再机械，且**全程不花钱**。

## 一、为什么之前听着机械

1. 原代码 `AVSpeechSynthesisVoice(language: "ja-JP")` 拿到的是系统**默认档**（compact，几百 KB，机械）。
   同一台设备上通常还装着 `Kyoko (Enhanced)` 这种增强档，原代码不去选它。
2. 整句一口气合成，语流一个调。
3. 没有任何真人素材。

## 二、被否掉的两个方案

| 方案 | 结论 |
| --- | --- |
| 自己录音 | 不要（用户明确否掉） |
| OpenAI `tts-1` / `gpt-4o-mini-tts` | **要花钱**：按字符计费（tts-1 约 $15 / 百万字符）。已彻底移除 |
| 音节拼接 | 更机械：来源不一的慢速单字录音，实测单字中位 0.68 秒（自然语速一拍约 0.15 秒） |

## 三、最终方案：两条免费路

### 路 1：系统高质量语音（零成本，兜底）

`Core/VoiceCatalog.swift`

- 列出设备全部 ja-JP 语音，按 `AVSpeechSynthesisVoiceQuality` 排序（premium > enhanced > default）；
- `current()` 记住用户选择，失效回退到最高档；
- `isUsingCompactVoice` 让界面提示「去下载增强语音」。

`SpeechText.split` 负责断句：句末标点优先，其次逗号（当前段 ≥ 6 字），否则按 24 字硬切；
段间 0.08 秒停顿。`Speech` 与 `SpeechLoop` 都走它。

### 路 2：语音包（免费 · 离线 · 接近真人）

用 `edge-tts`（微软 Edge 朗读接口，**免费、无需 API Key**）批量生成
`ja-JP-NanamiNeural` 的词读音，打成 `.voicepack`，App 装上后完全离线。

实测数据：

| 指标 | 值 |
| --- | --- |
| 采样率 / 比特率 | 24 kHz / 48 kbps 单声道，恒定 |
| 生成速度 | 约 3.7 条/秒（并发 6） |
| 全量 10660 条 | 约 50 分钟，约 100 MB（分五卷） |
| `たべる` | 1.54 秒 |
| `私たちはチームの連携を強化する必要があります。` | 4.90 秒（11 段，平均 0.45 秒/段） |

生成器：`tools/voice/gen_pack.py`，用法见 `tools/voice/README.md`。

**不需要常驻服务器**：脚本在任意一台能联网的电脑跑一次，产物丢到静态目录 / 对象存储 /
网盘直链，App 填地址下载即可。

## 四、`.voicepack` 格式

iOS 没有公开解压 API，所以不用 zip，改成自描述单文件：

```
magic     4 B   "JRJP"
version   2 B   uint16 大端 = 1
manifest  4 B   uint32 大端 = manifest 字节数
manifest  N B   UTF-8 JSON
payload   ...   各 mp3 按 offset 顺序拼接
```

manifest 每条：`{"key":"w-<词条id>","offset":0,"length":8123,"ext":"mp3"}`（offset 相对 payload）。
App 侧 `VoicePackInstaller.parseManifest` / `install` 负责切分落地，
`VoicePackInstaller.uninstall` 按清单删。

## 五、朗读优先级

```
VoicePack 本地音频  →  服务器合成 Nanami  →  系统高质量语音  →  系统默认语音
```

任一环缺失自动下一层；本地音频损坏时也退回 TTS，不静默失败。
服务器合成是 build 4 已有的第二层（用户决定保留）：包里没有的词走服务器 Nanami，
服务器失败或地址清空时才继续往下；N5/N4 包只覆盖 1558 条，其余词靠它才有 Nanami 的声音。

## 六、文件清单

### 新增

```
JianRiJi/Core/VoiceCatalog.swift          系统语音清单 / 选择 / 断句
JianRiJi/Core/VoicePack.swift             本地音频库（查找 / 写入 / 删除 / 统计）
JianRiJi/Core/VoicePackInstaller.swift    .voicepack 解析、下载、安装、卸载
JianRiJi/Features/Settings/VoiceSettingsView.swift   语音设置（系统语音 + 语音包）
Tests/SpeechTextTests.swift               断句单测
Tests/VoicePackFormatTests.swift          语音包格式单测
tools/voice/gen_pack.py                   edge-tts 批量生成器
tools/voice/README.md                     生成与部署说明
```

### 修改

```
JianRiJi/Core/Speech.swift                VoiceCatalog + 断句 + 本地音频优先 + 服务器合成兜底
JianRiJi/Core/SpeechLoop.swift            SpeechLine（带 audioKey）+ AVAudioPlayer + 服务器合成兜底
JianRiJi/Features/Settings/SettingsView.swift   「语音」入口
JianRiJi/Features/Study/ClassicModeView.swift   朗读带 audioKey
JianRiJi/Features/Study/ExampleSegmentDetailView.swift  朗读带 audioKey
JianRiJi/Resources/Info.plist             只留文件共享（便于拖入语音包）
```

### 已删除

```
JianRiJi/Core/TTSClient.swift             付费云端 TTS，整套移除
VoiceRecorder（原在 VoicePack.swift）     自录功能，整套移除
Info.plist 的 NSMicrophoneUsageDescription 随之移除
```

## 七、验收

| 验收项 | 期望 |
| --- | --- |
| 设置 → 声音 | 显示当前音质档位；默认档时有下载引导 |
| 设置 → 语音 → 系统语音 | 列出全部 ja-JP 语音，能选能试听，杀进程重进仍记住 |
| 设置 → 语音 → 语音包 | 填地址能读到 catalog.json，列出各卷 |
| 安装 N5 卷 | 进度条走完；「已安装 XXX 条」；本地音频文件数增加 |
| 安装后朗读 | 放的是包里的音频，飞行模式下仍能播 |
| 卸载 | 音频文件被删，条数回落 |
| 坏包 | 报「语音包内容不完整」，不留半包 |
| 没有语音包 | 自动用系统语音，功能不缺失 |

## 八、风险

1. edge-tts 不是微软公开承诺的 API，协议可能变。坏了就换 **VOICEVOX**
   （开源可离线，`/audio_query` + `/synthesis`），打包格式和 `gen_pack.py` 不用改。
2. `AVAudioPlayer.rate` 与 TTS 的 rate 不是一套刻度，代码里换算成
   `0.55 + rate * 0.6`（约 0.73~0.91 倍速），改动时别把换算去掉。
3. `VoicePackDownloader` 的 delegateQueue 固定在 `.main`，进度和 continuation 都在主线程改；
   改成后台队列要补锁。
4. 本批代码未编译验证，构建与单测以 `xcodebuild` 为准。
