# 交给 Muse 的施工提示词

> 用途：把「简日记」iOS 工程交给另一个 AI 工程师接手时，直接整段复制粘贴。
> 版本：v0.3.0（2026-11-03），对应 commit `ed1eb05`。

---

## 提示词正文（从这里开始复制）

````text
# 任务：接手并完成 iOS 工程「简日记 JianRiJi」

你是资深 iOS 工程师。目标：让这个 SwiftUI 工程在 Xcode 15 / iOS 16+ 上一次编译通过、可运行，
并在不改架构的前提下补完三个功能。

## 一、背景（必读，别跳）

工程根目录：JianRiJi/（若是压缩包，先解压到你自己的工作目录）
先按顺序读这三个文件：

- README.md                 功能清单、目录结构、构建方式、词表 schema
- docs/PARITY.md            与原版「识日」的逐屏对照、证据来源、本机能力边界
- docs/ARCHITECTURE.md      对 shiri_2.7.6.apk 的静态分析结论（模块树、后端接口、资源推断）

关键事实，先接受再动手：

1. 这是一个商业 App「识日」的**独立重写**。仓库里不含对方的任何代码、字体、SVG、音频、词库。
   你需要保持这个状态：**不要**去找、下载或还原对方的任何资源。
2. 该工程在 Windows 上写成，**从未被编译过一次**。存在零星编译错误是预期内的，
   你的第一优先级是编译通过，不是加功能、不是重构。
3. 工程用 XcodeGen 管理，JianRiJi.xcodeproj 不入库（.gitignore 已覆盖）。
4. 数据只有 80 条手写示例词（JianRiJi/Resources/seed_words.json），schema 见 README。
5. 现有代码规模：22 个 Swift 文件 / 约 3,100 行。

## 二、硬约束

1. 部署目标 **iOS 16.0**。禁止 iOS 17+ API，包括但不限于：
   topBarTrailing / topBarLeading、symbolEffect、@Observable、ContentUnavailableView、
   .scrollTargetBehavior、.containerRelativeFrame、#Preview 宏之外的 Xcode 16 新宏。
   需要这些效果时，用 iOS 16 的等价写法（.navigationBarTrailing、withAnimation、ObservableObject）。
2. 不引入任何第三方依赖（不加 SPM 包、不加 Pod）。只用系统框架：
   SwiftUI / Foundation / AVFoundation / Vision / WidgetKit / UIKit。
3. 不发网络请求。这个 App 是纯本地的，别加后端。
4. 不修改已有字段名（pos、example_zh、deckFilter 等）。只允许**新增可选字段**并给默认值。
5. 保留 MIT LICENSE 与 docs/ 下的全部文档。
6. 不做架构迁移（不要换 MVVM/TCA/RIBs，不要拆成 Swift Package），
   不要重命名现有文件与类型——除了第 3 阶段明确要求的新文件。

## 三、阶段一：让它编译（必须先完成，别跳步）

1) brew install xcodegen
2) cd JianRiJi && xcodegen generate
3) xcodebuild build \
     -project JianRiJi.xcodeproj \
     -scheme JianRiJi \
     -destination 'platform=iOS Simulator,name=iPhone 15' \
     -configuration Debug CODE_SIGNING_ALLOWED=NO
4) 逐个修编译错误。原则：**最小改动**。能改类型标注、能用等价 API 就改；
   不要顺手重排代码、不要"优化"你没读懂的实现。
5) 编译通过后跑测试：
   xcodebuild test -project JianRiJi.xcodeproj -scheme JianRiJi \
     -destination 'platform=iOS Simulator,name=iPhone 15' CODE_SIGNING_ALLOWED=NO
   Tests/SRSLogicTests.swift 必须全绿。
6) 交付一份「编译修复清单」，每个错误一行：文件:行 — 原因 — 修法。

如果你**没有 macOS / Xcode**：
不要假装编译通过。改为逐文件静态审查，输出「编译风险清单」，至少覆盖：
- 可用性（iOS 16 不支持的 API）
- 类型推断与泛型边界、@escaping 闭包捕获
- ViewBuilder 里 switch / if 的返回类型
- 属性包装器与 @MainActor 隔离
- Info.plist 与 project.yml 的键名一致性
并明确写出：本轮未经编译验证。

## 四、阶段二：运行时抽检

在模拟器把 App 跑起来，四条主流程必须走通，走不通就修：

1. 词本页 → 点任一词本 → 进入复习 → 点「点击查看词义」翻面 → 点四档评分 → 走到结算页
2. 学习页 → 假名判断（4 选 1）/ 拼写（敲 romaji）/ 连连看（配 4 组）/ 随身听（连播 2 轮）
3. 五十音：切 清音/浊音/拗音、切片假名、点格子听声
4. 查词：分别搜「学校」「がっこう」「gakkou」「学校」，都能出结果

已知待确认的隐患（原作者未验证，你必须实测）：
- Speech 的 AVAudioSession(.playback/.spokenAudio) 与随身听循环 Task 是否会互相打断
- SuishentingView 退出页面 / 切词 / 切后台时，Task 是否会叠加、重复朗读
- KanaJudgeView 在词本词数 < 4 时的降级路径（当前直接返回空题目）
- 复习页「下一词」在未翻面时禁用，是否会被误触跳过评分

## 五、阶段三：补三个功能（按顺序做，一个做完再下一个）

### 3.1 手写输入（对标原版的 ML Kit 方案）
- 新建 Features/Study/HandwritingView.swift
- 画布：iOS 16 用 SwiftUI Canvas + DragGesture 收集笔迹点，或包一层 PKCanvasView
- 识别：Vision 的 VNRecognizeTextRequest，recognitionLanguages = ["ja-JP"]，accurate 级别
- 把识别结果与当前词条（term / reading）比对，给对错反馈
- 判分接入现有 store.grade(word:grade:)：识别正确记 .good，错误记 .again
- 无相机权限需求（只处理内存里的 UIImage），不要加相机采集

### 3.2 打卡热力图
- 新建 Features/Study/HeatmapView.swift
- 数据源：Store.log（[ReviewLogEntry]），按自然日聚合
- 展示最近 12 周（7 行 × 12 列），纯 SwiftUI LazyVGrid 或 Canvas，别引图表库
- 颜色用 Theme.accent 的透明度阶梯；今天那格加描边
- 接进 StudyHubView 顶部卡片下方

### 3.3 动词 / 形容词变形表
- Word 新增可选字段 variants（[String: String]，默认 nil，保证旧 JSON 能解码）
- 新建 Core/Conjugation.swift，纯函数、无 UI、可单测
- 覆盖：五段动词 / 一段动词 / カ变 / サ变 的 ます形、て形、た形、ない形、可能形、意志形
- 形容词：い形容词与形容动词的 て形、过去形、否定形
- 词性从 Word.partOfSpeech 判断；判断不出来就降级为不显示，别猜
- 在词条详情页加一个「变形」区块
- 新建 Tests/ConjugationTests.swift，至少 12 条断言覆盖各类动词

## 六、交付与验证标准

每个阶段结束都要给我：
- git status（干净与否）
- 原样贴出执行过的命令与结果
- 改动文件清单
- 剩余风险

最终 Definition of Done：
- xcodegen generate && xcodebuild test 全绿
- App 在 iPhone 15 模拟器（iOS 16/17/18 任一）能启动，四个主流程走得通
- 仓库里没有任何来自「识日」的资源文件
- README 的「功能」表同步更新（新增的三个功能标 ✅）

## 七、报告格式（每阶段用它回话）

阶段：一 / 二 / 三
结果：通过 / 失败 / 部分通过
命令：<原样粘贴>
错误与修法：
- 文件:行 — 原因 — 修法
改动文件：
- path（一句话说明）
剩余风险：
- （没验证的部分必须写在这里，不许省略）

## 八、明确不要做的事

- 不要重写 UI 结构、不要换架构、不要为了"更优雅"而重构
- 不要联网搜索或下载「识日」的安装包、反编译产物、词库
- 不要把 80 条示例词扩成几千条（用户会自己换词表）
- 不要引入登录、支付、云同步、推送
- 不要新增 iOS 17+ API 来"简化"代码
````

## 复制结束

---

## 用法提示

1. **先给文件，再给提示词。** Muse 需要能读到 `docs/PARITY.md` 与 `docs/ARCHITECTURE.md`，否则它会退化成"凭想象重写一个日语 App"。
2. **把路径改对。** 提示词里写的是 `JianRiJi/`，如果你的实际路径不同，改掉再粘。
3. **如果 Muse 有 macOS 环境**：它能把阶段一、二真做完；如果没有，提示词里的"静态审查"分支会逼它承认「未编译」，而不是编一个通过的结果。
4. **别一次性丢三个阶段。** 先让它做完阶段一交清单，你确认编译真的过了，再放阶段二。否则它容易一口气改八十个文件，你没法判断哪里坏的。
5. **它每次说"已修复"时，要它贴 `xcodebuild` 的原始输出。** 只贴结论的，一律当没编译。
