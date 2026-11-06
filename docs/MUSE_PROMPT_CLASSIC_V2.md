# 经典模式 v2：例句逐词拆解 + 记忆技巧 + 洗脑循环

> 交接对象：接手「简日记」的工程师 / 编码智能体
> 前置阅读：`docs/MUSE_PROMPT.md`（项目硬约束）、`README.md`（功能表 / 目录 / 词表 schema）
> 本次范围：只改「经典模式」这一个界面 + 它依赖的三个新 Core 文件

## 一、这次做了什么

目标是提高经典模式背词页的信息密度。这次要做的六件事：

| # | 能力 | 本次实现位置 |
| --- | --- | --- |
| 1 | 顶部大字词形 + 假名 ・ romaji + 发音 / 慢速 | `ClassicModeView.titleBlock` / `actionPills` |
| 2 | 中间词性 + 中文释义 | `ClassicModeView.meaningBlock` |
| 3 | 参考例句显示读音、进词条自动读、可一键静音 | `ClassicModeView.referenceExample` + `SpeechLoop` |
| 4 | 例句**逐词拆分**，点任一段看它自己的解析与例句 | `JapaneseSegmenter` + `ExampleSegmentDetailView` |
| 5 | 记忆技巧 | `MnemonicBuilder` + `MnemonicAI` |
| 6 | 洗脑：循环朗读约 10 遍，随时可暂停 | `SpeechLoop.startLoop` + `ClassicModeView.bottomBar` |

## 二、文件清单

### 新增（4 个）

```
JianRiJi/Core/JapaneseSegmenter.swift          本地日语分词 + 注音引擎
JianRiJi/Core/SpeechLoop.swift                 带播完回调的朗读循环（单句 / 洗脑）
JianRiJi/Core/MnemonicBuilder.swift            记忆技巧本地生成 + AI 深化缓存
JianRiJi/Features/Study/ExampleSegmentDetailView.swift   点句中某段的详情页
Tests/JapaneseSegmenterTests.swift             分词 / 注音 / 记忆技巧单测
```

### 替换（1 个）

```
JianRiJi/Features/Study/ClassicModeView.swift
```

### 不动（重要）

`Store.swift`、`Word.swift`、`Speech.swift`、`Conjugation.swift`、`KanaRomaji.swift`、
`Theme.swift`、`Components.swift`、`FlowLayout.swift`、`AIClient.swift`、
`ReviewView.swift`（`QueueListView` 被复用）、`DictionaryView.swift`（`WordDetailView` 被复用）。

**不要改这些文件里的任何字段名、类型名或初始化签名。** 新代码只用它们已有的公开接口。

## 三、核心设计：为什么要自己写分词器

「例句逐词可点」必须先把句子切开。三条路：

1. 引第三方日语分词库（MeCab / Sudachi）—— 违反硬约束 2，且要带几十 MB 词典；
2. 服务端分词 —— 违反「默认不联网」；
3. **用现成的 10660 条词库当词典，自己做最长匹配** —— 本次采用。

`seed_words.json` 的覆盖率实测够用：`強化 / 連携 / チーム / 必要 / ある / する / 強い`
全部命中；不足的是助词、助动词、形式名词（`は / が / を / です / こと` 全不在词库里），
所以 `JapaneseSegmenter` 内置了一张 `functionWords` 表补上。

### 算法（已用真实词库验证，勿随意改动顺序）

```
对每个位置 i：
  1. 空白       → 跳过（不产出段）
  2. 标点       → 单段 punctuation
  3. 从长到短试 min(12, 剩余) 个候选：
       功能词  → particle
       词条    → word
       变形    → inflection
  4. 全不命中 → 单字符产出，按 汉字 / 假名 / 其它 分类
```

然后三条后处理：

1. **相邻同类未知块合并**：`た`+`ち` → `たち`；
2. **单字词条 + 紧随未知汉字合并**：`大`+`阪` → `大阪`（整块标未收录，读音给 nil）；
3. **白名单假名后缀并入前一个实词**：`私`+`たち` → `私たち`。
   白名单固定为 `たち / ら / ども / さん / さま / ちゃん / くん / がた`，
   **不要再放宽**——一度因为「长度 ≤ 3 的假名块都并入」把 `働く`+`こ` 粘成了不存在的词。

### 变形表的两个坑（已修，别改回去）

1. **形容动词的「〜で」形不能进索引**。
   `必要` 是「形容动词 / 名词」，`Conjugation` 会给它 `必要で`。若入索引，
   `必要です。` 会被切成 `必要で｜す`。处理：`if case .naAdjective = forms.kind { han[1] = nil }`。
   注意 `Conjugation.displayRows` 里的 `て形 必要で` 仍然要显示，那不受影响——
   只有「参与分词」这一侧剔除。

2. **要补ます形派生**。词库只有辞书形，`なりました` 必须靠
   「ます → ました / ません / ましょう / ませんでした」这一层派生才切得动。
   另外补「ます形词干」（`聞き`），否则 `聞きながら` 会被切成 `聞｜き`。

### 读音规则（不编造是硬要求）

| 段类型 | 读音来源 |
| --- | --- |
| `word` | 词条 `reading` 字段 |
| `inflection` | 用 `reading` 在同一个词性上再跑一遍 `Conjugation`，取对应形的假名；拿不到时若整段是假名则用原文，否则 **nil** |
| `particle` | 本身即假名 |
| `kana` | 本身即假名 |
| `unknownKanji` | **nil**（界面不标读音，详情页说明未收录） |

不要为了好看去按音读规则猜读音。

## 四、朗读与洗脑

`SpeechLoop` 自己持有 `AVSpeechSynthesizer`，用 `AVSpeechSynthesizerDelegate`
的 `didFinish` 实现「读完一句再读下一句」，替代原来按字数估算等待的写法。

要点：

- `speakOnce` 用 `withCheckedContinuation` 等 `didFinish`，**另加一道超时兜底**
  （`字数 × 0.45 + 3` 秒，上限 20 秒）。系统 TTS 在切后台时可能不给回调，
  没有兜底整个循环会永久挂住。
- `finishCurrent()` 必须幂等：`didFinish`、`didCancel`、超时三处都会调。
- 暂停 = `phase = .paused` + `stopSpeaking(.immediate)`；循环在每个句子前后
  都检查 `waitWhilePaused()`，所以暂停停的是「当前这一句」，不是整轮退出。
- 洗脑内容 = 词的 `reading` + 例句，共 10 遍；`remainingRounds` 给界面显示剩余次数。
- 自动朗读用 `.task(id: index)` 触发，**洗脑进行中不要抢读**（先判 `speaker.isRunning`）。

`Speech.swift` 保持不动：经典模式统一走 `SpeechLoop`，两者的 synthesizer
不在同一个界面同时发声。

## 五、记忆技巧

`MnemonicBuilder.local(for:)` 只用词库里成立的事实，最多 4 行：

| 行 | 内容 | 拿不到时 |
| --- | --- | --- |
| 读音 | 拍数 + 按拍切分（`きょうか` → `きょ・う・か`） | 无 reading 则整行不显示 |
| 词性 | 词性 + 一条接续提示（五段 / 一段 / サ变 / い形容词 / 形容动词 / 名词…） | 无 pos 则整行不显示 |
| 构词 | 汉字词拆两段，**两段都在词典里才给**（`強化` → `強` + `化`） | 否则不给，绝不硬凑 |
| 活用 | `Conjugation.displayRows` 前 4 行 | `conjugate` 返回 nil 则不给 |
| 同音 | 同读音、不同表记的词条 | 找不到则不给 |

`MnemonicAI` 是第二层：用户点「AI 深化」才走 `AIClient.chat`，结果按
`classic.mnemonic.ai.<词条id>` 存 `UserDefaults`，下次直接读缓存。
**不要把它改成进页面自动请求。**

## 六、硬约束（与 MUSE_PROMPT.md 一致，再强调）

1. 部署目标 **iOS 16.0**。新代码里没有 iOS 17+ API。
   `FlowLayout` 用的是 iOS 16 的 `Layout` 协议，`.task(id:)` 是 iOS 15+，都安全。
2. 不引任何第三方依赖。
3. 不新增/修改 `Store` 的持久化字段。本次只用了 `@AppStorage("classic.autoSpeakExample")`
   和 `UserDefaults("classic.mnemonic.ai.*")` 两个新键，都跟现有存档无关。
4. 不迁移架构、不重命名现有类型。
5. `JapaneseSegmenter.init()` 特意是 `internal` 而非 `private`，
   为的是单测能造独立实例喂小词库；**生产代码只用 `JapaneseSegmenter.shared`**。

## 七、需要你（接手方）做的事

### 必须做

1. 编译 + 跑全部单测：

```bash
brew install xcodegen
cd JianRiJi && xcodegen generate
xcodebuild build -project JianRiJi.xcodeproj -scheme JianRiJi \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO
xcodebuild test -project JianRiJi.xcodeproj -scheme JianRiJi \
  -destination 'platform=iOS Simulator,name=iPhone 15' CODE_SIGNING_ALLOWED=NO
```

2. 如果报 actor 隔离相关错误（项目是 `SWIFT_STRICT_CONCURRENCY: minimal`，
   正常应该只是 warning）：
   - `ClassicModeView` / `ExampleSegmentDetailView` 顶部加 `@MainActor`，或
   - 把 `SpeechLoop` 的 `@MainActor` 从类型级下移到方法级。
   `JianRiJiApp` 里 `@StateObject private var store = Store()`（Store 也是 @MainActor）
   已经验证过这个模式可行，优先照它的样子。

3. 真机 / 模拟器上跑一遍这六条验收：

| 验收项 | 期望 |
| --- | --- |
| 进词条 | 例句 300ms 后自动朗读（装了日语语音包时） |
| 点「静音」 | 朗读立刻停，之后切词不再自动读；再点恢复 |
| 例句排版 | 每段上方假名、中间词形带下划线、下方 romaji；未收录汉字只显示词形 |
| 点「私たち」 | 弹详情，显示「わたし ・ watashi」+ `私` 的释义；点「連携」显示「合作」 |
| 点「。」 | 不可点（无热区） |
| 记忆技巧 | `強化` 出现「读音 / 词性 / 构词」三行；无 AI Key 时不显示 AI 行也不报错 |
| 洗脑 | 点一次开始读，按钮变「暂停」并显示「剩余 N 次」；点一次暂停、再点继续；点 ✕ 立即停 |
| 读完 10 遍 | 自动回到「洗脑」初始态 |

### 建议做（不阻塞）

- 更新 `README.md` 功能表里「经典模式」那一行（第 16 行），补上例句逐词、记忆技巧、洗脑 10 遍。
- 更新 `docs/MUSE_PROMPT.md` 的版本号与「学习模式」描述。

### 不要做

- 不要把 `MnemonicBuilder` 改成每次进词条就请求 AI。
- 不要为了「看起来更像参考产品」而加用户数、真人语音、社区词义这类需要后端的东西——
  这个工程的原则是不造假。
- 不要给 `unknownKanji` 猜读音。
- 不要放宽 `suffixWhitelist`。
- 不要在 `prepare(words:)` 之外重建索引；它已经是幂等的。

## 八、已验证的事实（本地跑过，可直接作为预期）

用真实 `seed_words.json`（10660 条）切分，结果：

```
私たちはチームの連携を強化する必要があります。
→ 私たち | は | チーム | の | 連携 | を | 強化 | する | 必要 | が | あります | 。

私は毎朝六時に起きます。
→ 私 | は | 毎朝 | 六 | 時 | に | 起きます | 。

音楽を聞きながら勉強します。
→ 音楽 | を | 聞き | ながら | 勉強 | します | 。

ケーキを全部食べてしまいました。
→ ケーキ | を | 全部 | 食べて | しまいました | 。

来月から大阪で働くことになりました。
→ 来月 | から | 大阪(未收录,无读音) | で | 働く | こと | に | なりました | 。

必要です。
→ 必要 | です | 。          ← 形动词「〜で」那个坑的回归用例
```

变形索引规模约 20700 条，构建在 `onAppear` 一次性完成（本机量级约 100–200ms）。
若在低端机上感到卡顿，把 `prepare` 移到 `Task.detached`，但**不要**在未 prepare 时
给例句套用整句兜底排版而不做分词——分流逻辑会变得难以维护。

## 九、附：本次未编译验证

本次改动在**没有 Xcode 的机器**上完成，只做了逐文件静态审查 + 用 Python 原型在
真实词库上验证算法。**构建与单测均未经实跑**，请以上面的构建命令为准。
