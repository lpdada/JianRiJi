# 简日记 JianRiJi

一个自己重写的日语学习 iOS App：艾宾浩斯背单词、查词、五十音、听写。

> **这件事得先说清楚**：App Store 上的上架包拿不到，也不存在「反编译一个 iOS 版」这种路径。所以这个仓库是**照着玩法重新实现的原创工程**——没有「识日」的任何代码、词库、图标或界面素材，UI 与数据结构都是自己写的。想用，就自己编译；想上架，就自己签名。

---

## 功能

| 模块 | 已实现 | 说明 |
| --- | --- | --- |
| 词本 | ✅ | 按 JLPT 分档的词本列表，搜索、词数、进入即开始该词本 |
| 学习模式 | ✅ | 与识日 `screens/Memorize/*` 对齐的六个入口：经典复习 / 假名判断 / 拼写 / 连连看 / 随身听 / 手写 |
| 假名判断 | ✅ | 看词形选读音，四选一，答对答错都进同一套记忆曲线 |
| 拼写 | ✅ | 听读音、看释义，敲罗马字，答错自动显示答案 |
| 连连看 | ✅ | 日文配中文，四组一轮，配对成功推进度 |
| 随身听 | ✅ | 连播当前词本，可循环、可调间隔、支持后台音频 |
| 手写输入 | ✅ | 看中文意思，在画布上写词形，Vision ja-JP 识别判分，答对答错都进同一套记忆曲线 |
| 打卡热力图 | ✅ | 学习页顶部卡片下方，Store.log 按自然日聚合，最近 12 周（7 行 × 12 列），今天那格加描边 |
| 变形表 | ✅ | 词条详情页「变形」区块：五段 / 一段 / カ变 / サ变 的ます・て・た・ない・可能・意志形，い形容词与形容动词的て・过去・否定形；词性判断不出来就不显示 |
| 背单词 | ✅ | 对齐识日卡片页：进度条、词条大字、发音/慢速/收藏胶囊、「点击查看词义」薄荷块、例句区、底部列表 + 下一词 |
| 评分 | ✅ | 翻面后四档（忘了 / 模糊 / 记得 / 很熟），艾宾浩斯台阶 1→240 天，忘了的词 10 分钟后重来并回到本轮末尾 |
| 复习列表 | ✅ | 「列表速过」整轮摊平，当前项高亮，带 日文 / 中文 标签 |
| 查词 | ✅ | 对齐识日检索页：`〔假名〕` + 词性标签 + 释义，汉字/假名/romaji/中文四路检索 |
| 五十音 | ✅ | 对齐识日五十音页：清音 / 浊音 / 拗音三页签、薄荷格、悬浮「片假名」切换、点读 |
| 听写 | ✅ | 系统 TTS 念读音，敲 romaji 作答，即时判分（不动记忆进度） |
| 今日 | ✅ | 每日新词上限、单轮上限、进度环、连击、近七天柱状、历史正确率 |
| 数据 | ✅ | 全量 JSON 落盘到 Application Support，无账号、无后端、无网络请求 |
| 语法解析 | ❌ | 识日有，这里待做（变形表不是语法解析，只给词形变化） |
| 云同步 | ❌ | 没做。要同步自己接 CloudKit |

逐屏对照记录见 [docs/PARITY.md](docs/PARITY.md)，含商店截图与官方元数据来源。


## 目录

```
JianRiJi/
├── project.yml                     # XcodeGen 工程描述（工程文件不入库）
├── JianRiJi/
│   ├── App/
│   │   ├── JianRiJiApp.swift       # 入口
│   │   └── RootView.swift          # 五个 Tab
│   ├── Models/Word.swift           # 词条模型
│   ├── Core/
│   │   ├── SRS.swift               # 纯函数记忆算法（可单测）
│   │   ├── Store.swift             # 状态、队列、落盘、统计
│   │   ├── KanaData.swift          # 五十音数据
│   │   └── Speech.swift            # 系统 TTS 封装
│   ├── Design/                     # 主题与通用组件
│   ├── Features/                   # Home / Review / Kana / Dictionary / Dictation / Settings
│   └── Resources/
│       ├── seed_words.json         # 词库（当前 80 条手写示例）
│       ├── Info.plist
│       └── Assets.xcassets
└── Tests/SRSLogicTests.swift       # 记忆算法与解码单测
```

## 构建

要求：**Xcode 15+**、iOS 16.0+、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
brew install xcodegen
git clone https://github.com/lpdada/JianRiJi.git
cd JianRiJi
xcodegen generate
open JianRiJi.xcodeproj
```

不想装 XcodeGen 也行：

1. Xcode 里 New Project → iOS App，名字填 `JianRiJi`，Interface 选 SwiftUI。
2. 把 `JianRiJi/` 下所有 `.swift` 拖进工程（记得勾 Copy items if needed）。
3. 把 `Resources/seed_words.json`、`Info.plist`、`Assets.xcassets` 一起拖进去，确认 `seed_words.json` 在 Build Phases 的 Copy Bundle Resources 里。
4. Bundle Identifier 改成你自己的，签名选自己的 Team。

真机跑之前去「设置 → 辅助功能 → 朗读内容 → 声音 → 日语」下一个语音包，不然发音会退回默认语言。

## 词库

`Resources/seed_words.json` 是一个数组，字段：

```json
{
  "id": "w001",
  "term": "学校",
  "reading": "がっこう",
  "romaji": "gakkou",
  "meaning": "学校",
  "pos": "名词",
  "jlpt": "N5",
  "example": "学校まで歩いて十分です。",
  "example_zh": "走到学校十分钟。"
}
```

`example` 和 `example_zh` 可省。`id` 必须全局唯一——记忆进度是跟着 `id` 走的，改 `id` 等于换了一张新卡。

当前 80 条是手写的示例数据，只够把功能跑通。要正经用，换成你自己的词表（或者用 JMdict 之类的开放词典自己导）。**别把别人的商业词库扒进来。**

## 已知限制

- 没有笔顺动画。手写识别已做（学习页「手写」模式，Vision ja-JP，画布手写、内存图片识别）。
- 没有 AI 查词、没有语音识别打分。
- 单机存档：删 App 即清空，导出/导入还没做。
- 只在 SwiftUI 原生 iOS 16+ 上验证过设计，iPad 是能跑但没专门排版。

## 路线图

- [ ] 词表导入（CSV / TSV / Anki 导出格式）
- [ ] 学习记录导出与备份
- [ ] 笔顺动画（KanjiVG 之类的开放 SVG 数据）
- [ ] 小组件：今日剩余张数
- [ ] SwiftData 迁移（现在是手写 JSON）

## 许可

MIT，见 [LICENSE](LICENSE)。

字体、语音都用系统的，不额外分发任何字体文件。
