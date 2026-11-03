# 识日 APK 静态分析报告

分析对象：`C:\Users\peng\Downloads\shiri_2.7.6.apk`
工具：REA v6.8.0（`inspect_artifact` / `identify_flutter_build` / `inspect_dart_aot`）+ 归档枚举与 `libapp.so` 字符串池扫描。
**全程静态**，未运行 App、未联网调用其接口。

## 1. 包身份

| 项 | 值 |
| --- | --- |
| SHA-256 | `2a1840778c65a08f27770c49833196da25392879eff222605a58c8e38804b5f5` |
| 大小 | 80,574,635 字节（76.8 MB） |
| ZIP 条目 | 1,778（REA 图：1,779 occurrence / 1,671 node） |
| 格式 | APK（ZIP），签名校验未做 |

## 2. 技术栈：Flutter

| 事实 | 值 | 来源 |
| --- | --- | --- |
| `lib/arm64-v8a/libapp.so` | 15,074,224 字节，sha256 `ec17b2e5…2859f2f6` | `inspect_artifact` |
| `lib/arm64-v8a/libflutter.so` | 11,107,920 字节，build-id `0a7fde9b…` | 同上 |
| Dart snapshot hash | `1ce86630892e2dca9a8543fdb8ed8e22` | `identify_flutter_build` |
| AOT 快照布局 | kind 3（Dart 2.14 FullAOT 布局），VM data 18,256 B / isolate data 5,394,320 B | `inspect_dart_aot` |
| ABI | 仅 `arm64-v8a`（没有 armeabi-v7a / x86） | 归档枚举 |
| 引擎工具链 | clang 19.0.1（Android r530567e） | `libflutter.so` PT_NOTE |
| Dart 包名 | `package:shiri/...`，源码路径 `file:///Users/jin/www/shiri_flutter/` | 字符串池 |

> 工程路径 `/Users/jin/www/shiri_flutter` 与商店描述的「独立开发者 Jin」对得上——这台机器是 macOS 上构建的。

## 3. 模块拓扑（268 个 Dart 源文件）

| 目录 | 文件数 |
| --- | --- |
| `screens/` | 185 |
| `services/` | 26 |
| `widgets/` | 22 |
| `untils/` | 19（原文如此拼写，不是 utils） |
| `cache/` | 13 |
| 其他 | `const/`、`main`、`state/` |

### 3.1 一级功能域

```
screens/
├── Memorize/          ← 主体，约占一半页面
│   ├── MyLearn/       LearnMode、ComplexLearnMode、LearnJapanese、XiNaoSetting（洗脑）
│   ├── MyReview/      ClassicReview、QuickReview、Lianlianka（连连看）、SpilteReviewWord
│   ├── QuickLearn/    QuickLearnJapanese
│   ├── SearchWord/    WordDetail、AiSearchWord、ShowSentenceGrammar、CropImage、Xinao
│   ├── studyMode/     Shuaci（刷词）、SpellScreen02、SoundScreen03、SuishentingScreenV2（随身听）
│   ├── studyType/     DetailSpell、KnowVocabulary（假名判断）、SoundVocabulary03、SpellSentence
│   ├── StarTest/      测试：SelectTestVocabulary、TestType/SpellWidget03
│   ├── UserBook/      自建词本、歌词解析（ParseLyrics）、SearchBook、ShowBookDetail
│   ├── vocabulary/    VerbVariant（动词变形）、AdjVariant（形容词变形）、Phrase、SearchKanji
│   ├── Grammar/       语法学习与测试
│   ├── Setting/       学习/复习/拼写/随身听/词条显示顺序
│   └── UserData/      SignInHeatmapCalendar（打卡热力图）、DataDetail
├── Sentence/          句子库：自定义、分组、分享、背诵、句子洗脑
├── Phonetic/          PhoneticScreen（五十音）+ WordStrokeWidget（笔顺）
├── GroupActive/       组队打卡：TeamSquare、CreateTeam、TeamDetail、TeamSuccess
├── Account/           会员、豆币、积分兑换、JLPT 兑换、错误词、收藏、笔记、PC 扫码登录
└── Common/            登录、首页动画（樱花/落叶/雨/雪/流星）、WebView、加载
```

### 3.2 services（26）

`Account / AiDialog / Ai / AppleTranslation / Book / CustomAudio / Data / Device / Duobi / ExportPdf / FavoriteSentence / GroupMemorizeActive / Home / PcLogin / Recognition / Sentence / StudyGrammar / StudyVocabulary / Translate / UserErrorWord / UserMessage / UserNote / User / Widget / Word / VocabularyData`

### 3.3 untils（19）—— 音频是重点

`AudioBackgroundManage`、`AudioPlaybackChannel`、`AudioPlaybackScope`、`AudioPlayerHandler`、`AudioSessionCoordinator`、`AudioSourceRepository`、`MyAudioManage`、`RecordingController`、`SilenceAudio`、`StudyAudioOwner`、`WhiteNoiseManager`、`HttpClient`、`ios_safe_area`、`CustomColor`、`CommonStyle`…

> 从这组命名可判断：**App 有一套自建的音频会话协调层**，负责「学习时后台播放 / 跟读录音 / 白噪音 / 锁屏控制」互相不打架。这是它最工程化的部分。

## 4. 后端与资源

### 4.1 主机

| 主机 | 用途 |
| --- | --- |
| `jpshiri.jingqueyun.com` | 主 API |
| `shiri.cdn.jingqueyun.com` | 静态资源（汉字 SVG、教学视频、白噪音） |
| `translate.jingqueyun.com` | 翻译服务 |
| `shiri.jingqueyun.com` | 官网 / 隐私政策 / PDF |

### 4.2 API 域（235 个路径，节选）

| 域 | 关键端点 | 含义 |
| --- | --- | --- |
| `/MobileBook/*` | `getBookList`、`setUserStudyBook`、`shuffleBookWords`、`relearnBookV3`、`parseLyrics` | 词本清单、切换学习书、打乱、重学、**歌词解析建词本** |
| `/MobileStudyVocabulary/*` | `getNeedReviewWords`、`getReviewVocabularyV5`、`addReviewLogV3`、`saveErroWord` | 复习队列、复习日志、错词 |
| `/MobileStudySentence/*` | `getNeedStudySentenceV2`、`updateReviewSentence`、`reStudyGroup` | 句子学习与复习 |
| `/MobileVocabularyData/*` | `getAllMasteredWords`、`getPageResidualWords`、`searchUserWord`、`getSuiShentingData` | 各类词单与**随身听数据** |
| `/mobileWord/*` | `search?word=`、`getKanjiRelatedWords`、`appTranslate`、`useCustomMean` | 查词、汉字关联词、翻译、自定义释义 |
| `/MobileAiSearch/*`、`/MobileAi/*` | `searchWordByAiV2`、`wordExplain`、`getAiGrammarStreamV2` | AI 查词与语法流式解析 |
| `/MobileAudio/*` | `getWordAudioV2`、`uploadM4aAudio`、`setDefaultAudio`、`submitErrorAudio` | 单词音频、**用户上传自己的读音**、报错 |
| `/MobileRecognition/parseStr` | — | 手写/OCR 结果解析入口 |
| `/MobileStudyGrammar/*` | `getGrammarList`、`getUserTestGrammarQuestions`、`saveGrammarTestLog` | 语法书与语法测试 |
| `/MobileTranslate/*` | `translateJaToCh`、`getQuota` | 翻译与配额 |
| `/MobileGroupMemorizeActive/*` | `createActiveGroup`、`joinTeam`、`startChallenge`、`getTeamSquare` | **组队打卡** |
| `/MobileDevice/*`、`/MobileDuobi/*` | `buqian`（补签）、`checkDuobi`、`reduceDuobi`、`exchangeJlptVip` | 打卡、豆币、会员兑换 |
| `/MobileExportPdf/*` | `getPdfVocabulary`、`savePdfVocabulary` | 导出 PDF 词表 |
| `/user/*` | `mobileLogin`、`sendSmsRegister`、`confirmBindPhone` | 手机号登录 |

### 4.3 资源 → 功能（推断）

| 资源 | 数量/大小 | 推断 |
| --- | --- | --- |
| `assets/svg/030xx.svg` | 约 300+ 个，2 KB 级 | 假名与汉字的**笔画字形**，文件名是 Unicode 码点（`03041`→U+3041 ぁ），用于笔顺/字形展示 |
| `assets/audio/fayin/*.mp3` | 120 个 / 1.7 MB | 五十音发音，文件名是假名（URL 编码）或罗马字 |
| `assets/audio/week/*.mp3` | 7 个 | 星期读法（火/金/木/日/水/土/月） |
| `assets/images/pixel/*.png` | 20 个 | 像素图标，直接暴露功能：`spell-keyboard`（拼写）、`review-loop`（复习循环）、`kana-tile`（假名）、`verb-form`（动词变形）、`particle-book`（助词）、`study-alarm`（学习提醒）、`word-book`、`medal-premium`、`star-point`、`gift-pack` |
| `assets/images/new_index/*.png` | 22 个 | 首页功能：`calendar`、**`diary`**、`crown`（会员）、`setting`、`tree`、`letter`、`gift-box` |
| `assets/images/white_noise/*.png` | 9 个 | 白噪音（雨/火/鸟/水/风扇/深度），音频走 CDN |
| `assets/images/widget_bg/mosaic_bg_*.png` | 9 个 | 桌面小组件背景，按 1000/2000/…/8000 词档位解锁 |
| `assets/lottie/*.json` | 5 个 | 完成、庆祝、录音、加载动画 |
| `assets/fonts/NotoSansJP-*.ttf`、`NotoSansSC-*.ttf` | 5 个，约 32 MB | 日文/简体中文字体，占包体大头 |

### 4.4 第三方 SDK

`umeng`（友盟统计，`libumeng-spy.so`）、`tnet`（腾讯网络 `libtnet-3.1.14.so`）、华为 HMS/AGC、Firebase（encoders/annotations）、`play-services-mlkit-text-recognition-japanese`、`rive_text`（Rive 动画）、`audio_service`、`datastore`。

> **手写的实现方式**：`libmlkit_google_ocr_pipeline.so` + `text-recognition-japanese.properties` + 日文 OCR 模型（`Jpan_ctc/lstm_model.fb`，886 KB）——手写是**画布 + ML Kit 日文 OCR 识别**，不是笔顺识别。iOS 侧对应 `Vision` 的 `VNRecognizeTextRequest`（`ja-JP`）。

## 5. 移植到 iOS 的映射

| 识日能力 | Android 实现 | iOS 对应 |
| --- | --- | --- |
| UI | Flutter | 可选 Flutter 复用；本项目走原生 SwiftUI |
| 发音 | 服务端 mp3 + 本地 fayin | `AVSpeechSynthesizer`（已用）/ `AVAudioPlayer` + CDN |
| 随身听 | audio_service + 自建音频协调层 | `AVAudioSession(.playback)` + Now Playing + `MPRemoteCommandCenter` |
| 手写识别 | ML Kit text-recognition-japanese | `Vision` `VNRecognizeTextRequest`（`ja-JP`，iOS 13+） |
| 跟读录音 | `RecordingController` + `uploadM4aAudio` | `AVAudioRecorder` + 上传 |
| 笔顺 | `assets/svg/030xx.svg` | 同源 SVG（需自行获得授权）或 KanjiVG（CC BY-SA） |
| 白噪音 | CDN 音频 + `WhiteNoiseManager` | `AVAudioEngine` + 本地/远程音频 |
| 小组件 | `WidgetService` + `mosaic_bg_*` | `WidgetKit` + App Group |
| 打卡热力图 | `SignInHeatmapCalendar` | 自绘 Calendar Heatmap |
| 组队打卡 | `GroupMemorizeActive` | 需后端；本地可做单机版 |
| 支付/会员 | `setUpgradeMember`、豆币体系 | StoreKit 2（订阅） |
| 登录 | 手机号 + 短信 | 同（需短信服务商） |

## 6. 未能回答的问题

1. 词库内容本身——`getBookList` 从服务端下发，本地没有词表文件；抓包才能看到字段。
2. 艾宾浩斯具体参数（档位、间隔、逾期策略）——在 `services/StudyVocabularyService` 里，需反编译 Dart AOT 才能读；当前工具链只做字符串层。
3. 会员价格与免费额度边界。
4. 「洗脑循环」的具体调度（间隔、是否打乱）。
5. 手写识别的后处理（`/MobileRecognition/parseStr` 的入参格式）。

## 7. 结论

识日是一个**Flutter + 自建后端**的重型学习工具：词库、句子库、语法书、发音、AI 解析全在服务端，客户端主要承担交互与调度。因此「完美复刻」在纯客户端层面做不到——**它的内容资产不在包里**。

能做的是：复刻交互骨架（我们已做）+ 用 Apple 原生能力替换它的 Android 依赖（TTS 换 mp3、Vision 换 ML Kit、WidgetKit 换 WidgetService）。
