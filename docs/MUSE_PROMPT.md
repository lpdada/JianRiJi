# 项目简介（给接手的人）

> 用途：把「简日记」iOS 工程交给另一个工程师接手时，先读这篇，再读 README。
> 版本：v0.4.0（2026-11-04），对应主分支最新提交。

## 一、这是什么

「简日记 JianRiJi」是一个日语学习 iOS App（SwiftUI，纯客户端）：

- 艾宾浩斯背单词（四档评分，台阶 1→240 天）、查词、五十音、听写
- 学习模式：经典复习 / 假名判断 / 拼写 / 连连看 / 随身听 / 手写 / 经典模式
- 语法学习：270 个分级语法点（N5 30 / N4 30 / N3 30 / N2 150 / N1 30）
- 词条详情 AI 讲解：点一次发一次 OpenAI 兼容请求（见下方「网络」）

数据规模：词库 10660 条（N5 803 / N4 755 / N3 1827 / N2 3216 / N1 4059），
记忆进度跟着词条 `id` 走，改 `id` 等于换了一张新卡。
学习存档是本地 JSON，落盘到 Application Support，无账号、无后端。

## 二、硬约束

1. 部署目标 **iOS 16.0**。禁止 iOS 17+ API，包括但不限于：
   topBarTrailing / topBarLeading、symbolEffect、@Observable、ContentUnavailableView、
   .scrollTargetBehavior、.containerRelativeFrame。
   需要这些效果时，用 iOS 16 的等价写法（.navigationBarTrailing、withAnimation、ObservableObject）。
2. 不引入任何第三方依赖（不加 SPM 包、不加 Pod）。只用系统框架：
   SwiftUI / Foundation / AVFoundation / Vision / WidgetKit / UIKit / Security（Keychain）。
3. 不修改已有字段名（pos、example_zh、deckFilter 等）。只允许**新增可选字段**，
   且新增字段不要给 Decodable 默认值——有默认值的可选属性会被合成 Decodable 跳过，
   导致 JSON 里明明有值却解出来是 nil（v0.3.0 的教训）；构造处显式传 nil。
4. 不做架构迁移（不要换 MVVM/TCA/RIBs，不要拆成 Swift Package），
   不要重命名现有文件与类型——除了任务明确要求的新文件。
5. 工程用 XcodeGen 管理，JianRiJi.xcodeproj 不入库（.gitignore 已覆盖）。
   本机无 Xcode 时不要假装编译通过，改为逐文件静态审查并明确写出未经编译验证。

## 三、构建与测试

```bash
brew install xcodegen
cd JianRiJi && xcodegen generate
xcodebuild build -project JianRiJi.xcodeproj -scheme JianRiJi \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO
xcodebuild test -project JianRiJi.xcodeproj -scheme JianRiJi \
  -destination 'platform=iOS Simulator,name=iPhone 15' CODE_SIGNING_ALLOWED=NO
```

CI 在 GitHub Actions（macos-15 + Xcode 16）上跑 build.yml；
免签 IPA 由 `Build unsigned IPA` 工作流手动触发（workflow_dispatch，
推送不会自动跑），不要只等它自己出现。
查构建失败要拉完整任务日志（`gh api .../actions/jobs/<id>/logs`），
不要用 `gh run view --log-failed`（它会丢错误行）。

## 四、网络

默认不联网。唯一会发网络请求的是用户主动用的 AI 功能
（词条详情「AI 讲解」、设置页「测试连接」），请求只发给设置里选中的厂商地址，
Key 按厂商存在系统 Keychain，不进学习存档，不发给其他任何服务器。

## 五、许可

代码与自编内容：MIT，见 LICENSE。
例外：`seed_words.json` 中 10641 条主词库遵循 CC BY-NC 4.0
（仅限非商业使用、须署名，见 README「词库」一节），MIT 不覆盖这部分数据；
App 目前不收费、不商用，符合该许可，商用前必须先换掉这部分词库。
不要引入来源不明或许可证不允许的词库、字体、音频、图片资源。

## 六、接手检查清单

1. 先读 README 的功能表、目录结构、词表 schema，再动手。
2. 改动前确认影响面：删功能先查共用调用方，不只按名字查；
   取文本类改动先验宿主到底给了多少，不默认它给全了。
3. 改动后跑通构建与全部单测，再提交；提交信息写清改了什么、为什么。
4. 不改仓库可见性、不建 Release、不动其他分支与标签，除非用户明确要求。
