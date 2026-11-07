# 语音包生成器（免费 · 无需 API Key）

给「简日记」批量生成日语词读音，产出 App 能直接安装的 `.voicepack`。

## 为什么是 edge-tts

| 方案 | 花钱 | 需要 Key | 音质 |
| --- | --- | --- | --- |
| OpenAI `tts-1` | **是**（按字符计费） | 要 | 好 |
| edge-tts（本方案） | **否** | **不要** | 好（`ja-JP-NanamiNeural`，微软神经语音） |
| VOICEVOX（自建） | 否 | 不要 | 好，偏动漫风格，需要部署引擎 |
| 系统 TTS | 否 | 不要 | 增强档不错，默认档机械 |

edge-tts 用的是微软 Edge 浏览器的「大声朗读」接口，**免费、不要 Key**，日语有
`ja-JP-NanamiNeural`（女）和 `ja-JP-KeitaNeural`（男）两个神经语音。
实测输出：24 kHz / 48 kbps 单声道 / 恒定码率，`たべる` 1.54 秒，
`私たちはチームの連携を強化する必要があります。` 4.90 秒（平均每段 0.45 秒，是自然语速）。

## 生成

```bash
pip install edge-tts

# 试跑 20 条，先确认能出声
python gen_pack.py --words seed_words.json --out ./packs --level N5 --limit 20

# 正式出一卷
python gen_pack.py --words seed_words.json --out ./packs --level N5

# 五个级别全出
python gen_pack.py --words seed_words.json --out ./packs --all
```

参数：

| 参数 | 说明 |
| --- | --- |
| `--words` | `seed_words.json` 路径（工程里 `JianRiJi/Resources/seed_words.json`） |
| `--out` | 输出目录 |
| `--level` | 只出某一级（N5 / N4 / N3 / N2 / N1） |
| `--all` | 五级各出一卷 |
| `--limit` | 只出前 N 条，用来试跑 |
| `--voice` | 默认 `ja-JP-NanamiNeural`，可换 `ja-JP-KeitaNeural` |
| `--rate` | 默认 `-10%`（稍慢，适合学习） |
| `--concurrency` | 默认 6；被封就降到 3 |

实测速度约 **3.7 条/秒**，全量 10660 条约 **50 分钟**。

## 产物

```
packs/catalog.json       App 先读它
packs/n5.voicepack       单卷
```

体积参考（每条约 8–10 KB）：

| 卷 | 词条数 | 约 |
| --- | --- | --- |
| N5 | 803 | 7 MB |
| N4 | 755 | 7 MB |
| N3 | 1827 | 17 MB |
| N2 | 3216 | 30 MB |
| N1 | 4059 | 38 MB |

## 怎么给 App 用

App 端：**设置 → 语音 → 语音包**，填一个目录地址，点「读取目录」，选卷安装。
装完之后朗读优先用包里的音频，**完全离线**。

### 需要服务器吗

不需要专门的服务器，三种放法都行：

1. **任意静态目录**：把 `catalog.json` 和 `.voicepack` 丢到你的 nginx / 对象存储 / GitHub Pages，
   地址填那个目录的 URL。
2. **网盘直链**：只要能给出直链（不是预览页），一样能用。
3. **完全离线**：在你自己电脑上生成好，然后把 `.voicepack` 用「文件」App 放进
   `简日记/VoicePacks/`（需要先手动安装一次以生成清单，或直接用第 1 种）。

> 生成脚本本身跑在哪都行：Windows / macOS / Linux，只要能联网、能 `pip install edge-tts`。
> 不需要 GPU，不需要 Docker。

## `.voicepack` 格式

iOS 没有公开的解压 API，所以不用 zip，改成自描述的单文件：

```
magic     4 B   "JRJP"
version   2 B   uint16 大端 = 1
manifest  4 B   uint32 大端 = manifest 字节数
manifest  N B   UTF-8 JSON
payload   ...   各音频按 offset 顺序拼接
```

manifest 里每条：`{"key": "w-<词条id>", "offset": 0, "length": 8123, "ext": "mp3"}`
（offset 相对 payload 起点）。App 侧 `VoicePackInstaller.parseManifest` 按这个切。

## 注意

- edge-tts 不是微软公开承诺的 API，可能哪天改协议。改坏了就换 VOICEVOX
  （开源、可离线部署，`/audio_query` + `/synthesis` 两接口），格式和打包脚本照抄即可。
- 生成的内容仅供个人学习使用；对外分发要注意音源的使用条款。
- 语速 `-10%` 是给学习调的，觉得慢了改成 `0%`，快了改 `-20%`。
