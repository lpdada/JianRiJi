# 数据说明

## 1. 现在仓库里有什么

| 文件 | 内容 | 规模 |
| --- | --- | --- |
| `JianRiJi/Resources/seed_words.json` | 词条 | 10660 词 |
| `JianRiJi/Resources/books.json` | 词书定义 | 13 本 |
| `JianRiJi/Resources/grammar_points.json` | 语法点 | 270 条（N5 30 / N4 30 / N3 30 / N2 150 / N1 30） |

主词库来自 anki-jlpt-decks（作者 egg rolls），**CC BY-NC 4.0**：仅限非商业使用，
署名见 README 的授权说明。MIT 只覆盖代码和自编内容，不覆盖这份词库；
商用必须先换掉它。

## 2. 词书（books.json）

词书只是筛选规则，不另外存一份词。`filterType` 的含义：

| filterType | 规则 |
| --- | --- |
| `all` | 全部词条 |
| `book` | `resolvedBook == filterValue`（见下） |
| `jlpt` | `jlpt == filterValue` |
| `tag` | `tags` 包含 `filterValue` |
| `learned` | 已经开始学的词（不是新词） |
| `favorite` | 星标收藏的词 |

词条的 `book` 字段省略时按 `jlpt` 自动兜底：N5→初级上 / N4→初级下 /
N3→中级 / 其他→高级。`book` 字段只是本地归类标签，不是教材内容。

现有词库的 10660 词都没有 `book` 和 `tags` 字段，所以：

- 初级上 803 / 初级下 755 / 中级 1827 / 高级 7275，全部来自级别兜底；
- JLPT N5 803 / N4 755 / N3 1827 / N2 3216 / N1 4059；
- **日常高频目前是 0 词**：它筛的是 `tags` 含「日常」的词，现有词没有标签，
  要用导入工具的 `tags` 列补。

## 3. 词条 schema

```json
{
  "id": "egg-0cf8b148-2ed7-11ef-a183-99ad05e145f0",
  "term": "学校",
  "reading": "がっこう",
  "romaji": "gakkou",
  "meaning": "学校",
  "pos": "名词",
  "jlpt": "N5",
  "example": "学校まで歩いて十分です。",
  "example_zh": "走到学校十分钟。",
  "example_furigana": "学校[がっこう]まで歩[ある]いて十分[じゅっぷん]です。",
  "note": "精讲解析……",
  "book": "初级上",
  "tags": ["日常"]
}
```

- `id` 全局唯一，进度跟着它走，**不要改**。导入的新词用 `import-000001` 起。
- `book`、`tags`、`note`、`example_furigana` 都可省略，缺键解码为 nil。
- 词条的 Swift 模型里这些可选字段**不能给默认值**：带默认值的属性会被合成
  Decodable 跳过，JSON 里有值也会解成 nil（CI 单测已实证）。

## 4. 导入自己的词表

```bash
python3 tools/import_words.py --input my_words.csv --book "初级上"
python3 tools/import_words.py --input jlpt_n3.tsv --book "中级" --dry-run
python3 tools/import_words.py --input fix.csv --update      # 覆盖已存在的词
```

CSV/TSV 表头（大小写不敏感，多余列忽略）：

```
term,reading,romaji,meaning,pos,jlpt,book,example,example_zh,example_furigana,note,tags
```

- 必填：`term`、`reading`、`meaning`
- `tags` 用分号分隔：`日常;食物`
- 以 `term + reading` 判重；`--update` 时覆盖同名词条
- `--dry-run` 只输出新增条数，不写盘
- 写回前会解析一次 JSON 自校验，失败不动原文件

## 5. 从哪拿词表

这里只给方向，不给下载链接——各类词表的授权差别很大，选之前先看许可证：

| 来源 | 许可 | 说明 |
| --- | --- | --- |
| JMdict（EDRDG） | CC BY-SA | 日英词典，含读音、词性；可转成中文释义后导入 |
| KANJIDIC2 | CC BY-SA | 汉字信息，适合做笔顺/字形 |
| jmdict-simplified | 同上 | JMdict 的 JSON 版，解析省事 |
| 自建 | 你的 | 上课记的词、追剧记的词，最贴自己 |

**不要**把商业教材（新标日、红宝书等）的词表直接拷进仓库分发。教材词表有版权，
自己用可以，公开仓库会出事。

## 6. 语法数据

`grammar_points.json` 的字段：

| 字段 | 说明 |
| --- | --- |
| `level` | N5–N1 |
| `title` | 句型，如「〜は〜です」 |
| `connection` | 接续 |
| `meaning` | 意义 |
| `example` | 例句（日文） |
| `exampleReading` | 例句假名 |
| `exampleZh` | 例句中文 |
| `note` | 备注 |
| `tag` | 分类，如「判断」「助词」 |
| `examples` | 可选，`[{ "ja": ..., "zh": ... }]`，多条例句；缺键时用单条 `example` |

270 条是自编骨架。搜索命中句型、意义、接续、备注、例句读音、标签、例句。
