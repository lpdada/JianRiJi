#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用 edge-tts 给「简日记」批量生成日语词读音，打包成 App 能直接装的 .voicepack。

edge-tts 用的是微软 Edge 的朗读接口：免费、不需要 API Key、日语有
ja-JP-NanamiNeural（女）和 ja-JP-KeitaNeural（男）两个神经语音，质量接近真人。

用法（在任意一台能联网的电脑上跑都行，Windows / macOS / Linux 均可）：

    pip install edge-tts

    # 先试 20 个，确认能出声
    python gen_pack.py --words seed_words.json --out ./packs --level N5 --limit 20

    # 正式生成 N5 一整卷
    python gen_pack.py --words seed_words.json --out ./packs --level N5

    # 五个级别全出（约 1.5~2 小时，取决于网络）
    python gen_pack.py --words seed_words.json --out ./packs --all

产物：

    packs/catalog.json         App 先读它，列出有哪些包
    packs/n5.voicepack         单个包（自定义格式，见下）

.voicepack 格式（App 端用 Foundation 就能解开，不需要解压库）：

    magic     4 B   b"JRJP"
    version   2 B   uint16 大端 = 1
    manifest  4 B   uint32 大端 = manifest 字节数
    manifest  N B   UTF-8 JSON
    payload   ...   各音频按 offset 顺序拼接

manifest 里每个 entry：{"key": "w-<词条id>", "offset": 0, "length": 8123, "ext": "mp3"}
offset 相对于 payload 起点。
"""

from __future__ import annotations

import argparse
import asyncio
import io
import json
import os
import struct
import sys
import time
from datetime import datetime, timezone

try:
    import edge_tts
except ImportError:
    sys.exit("缺 edge-tts：先跑 pip install edge-tts")

MAGIC = b"JRJP"
VERSION = 1

DEFAULT_VOICE = "ja-JP-NanamiNeural"
DEFAULT_RATE = "-10%"

LEVELS = ["N5", "N4", "N3", "N2", "N1"]


def load_words(path: str) -> list[dict]:
    with open(path, encoding="utf-8") as f:
        words = json.load(f)
    if not isinstance(words, list):
        raise ValueError("seed_words.json 顶层应该是数组")
    return words


def spoken_text(word: dict) -> str:
    """念什么：优先假名读音（动词是辞书形），没有就用表记。"""
    reading = (word.get("reading") or "").strip()
    term = (word.get("term") or "").strip()
    text = reading or term
    # 全角括号之类的痕迹去掉，免得念出奇怪的东西
    return text.strip()


async def synth_one(text: str, voice: str, rate: str, retries: int = 3) -> bytes:
    last_error: Exception | None = None
    for attempt in range(retries):
        try:
            communicate = edge_tts.Communicate(text, voice, rate=rate)
            buffer = io.BytesIO()
            async for chunk in communicate.stream():
                if chunk.get("type") == "audio" and chunk.get("data"):
                    buffer.write(chunk["data"])
            data = buffer.getvalue()
            if not data:
                raise RuntimeError("空音频")
            return data
        except Exception as exc:  # noqa: BLE001 - 网络抖动重试就够，不必细分
            last_error = exc
            await asyncio.sleep(1.2 * (attempt + 1))
    raise RuntimeError(f"合成失败：{text!r}：{last_error}")


async def build_pack(
    words: list[dict],
    pack_id: str,
    title: str,
    voice: str,
    rate: str,
    concurrency: int,
    out_dir: str,
) -> dict:
    semaphore = asyncio.Semaphore(concurrency)
    total = len(words)
    done = 0
    results: dict[str, bytes] = {}
    failures: list[str] = []
    started = time.time()

    async def worker(word: dict) -> None:
        nonlocal done
        text = spoken_text(word)
        key = f"w-{word['id']}"
        if not text:
            done += 1
            return
        async with semaphore:
            try:
                results[key] = await synth_one(text, voice, rate)
            except Exception as exc:  # noqa: BLE001
                failures.append(f"{key} {word.get('term')}: {exc}")
        done += 1
        if done % 20 == 0 or done == total:
            elapsed = time.time() - started
            speed = done / elapsed if elapsed > 0 else 0
            eta = (total - done) / speed if speed > 0 else 0
            print(
                f"  [{pack_id}] {done}/{total}  "
                f"{speed:.1f} 条/秒  剩余约 {eta / 60:.1f} 分钟",
                flush=True,
            )

    await asyncio.gather(*(worker(w) for w in words))

    # 按原始词表顺序拼 payload，保证同一版本产出的包字节稳定
    payload = io.BytesIO()
    entries: list[dict] = []
    for word in words:
        key = f"w-{word['id']}"
        data = results.get(key)
        if not data:
            continue
        offset = payload.tell()
        payload.write(data)
        entries.append({"key": key, "offset": offset, "length": len(data), "ext": "mp3"})

    manifest = {
        "version": VERSION,
        "pack": pack_id,
        "title": title,
        "voice": voice,
        "rate": rate,
        "count": len(entries),
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "entries": entries,
    }
    manifest_bytes = json.dumps(manifest, ensure_ascii=False, separators=(",", ":")).encode("utf-8")

    pack_path = os.path.join(out_dir, f"{pack_id}.voicepack")
    with open(pack_path, "wb") as f:
        f.write(MAGIC)
        f.write(struct.pack(">H", VERSION))
        f.write(struct.pack(">I", len(manifest_bytes)))
        f.write(manifest_bytes)
        f.write(payload.getvalue())

    size = os.path.getsize(pack_path)
    print(f"  [{pack_id}] 写出 {pack_path}  {size / 1024 / 1024:.1f} MB  {len(entries)} 条", flush=True)
    if failures:
        print(f"  [{pack_id}] 失败 {len(failures)} 条：", flush=True)
        for line in failures[:10]:
            print(f"    - {line}", flush=True)

    return {
        "id": pack_id,
        "title": title,
        "file": f"{pack_id}.voicepack",
        "count": len(entries),
        "bytes": size,
    }


def select_words(words: list[dict], level: str | None, limit: int | None) -> list[dict]:
    if level:
        chosen = [w for w in words if (w.get("jlpt") or "") == level]
    else:
        chosen = list(words)
    # 去掉没有 id 的脏数据
    chosen = [w for w in chosen if w.get("id")]
    if limit:
        chosen = chosen[:limit]
    return chosen


async def main() -> None:
    parser = argparse.ArgumentParser(description="用 edge-tts 生成简日记语音包")
    parser.add_argument("--words", required=True, help="seed_words.json 路径")
    parser.add_argument("--out", required=True, help="输出目录")
    parser.add_argument("--level", choices=LEVELS, help="只生成某一个级别")
    parser.add_argument("--all", action="store_true", help="五个级别各出一卷")
    parser.add_argument("--limit", type=int, help="只生成前 N 条，用来试跑")
    parser.add_argument("--voice", default=DEFAULT_VOICE, help=f"语音，默认 {DEFAULT_VOICE}")
    parser.add_argument("--rate", default=DEFAULT_RATE, help=f"语速，默认 {DEFAULT_RATE}")
    parser.add_argument("--concurrency", type=int, default=6, help="并发数，默认 6")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    words = load_words(args.words)
    print(f"词库 {len(words)} 条，语音 {args.voice}，语速 {args.rate}")

    if not args.level and not args.all:
        print("没指定 --level 或 --all，默认按 N5 出一卷。")
        args.level = "N5"

    packs: list[dict] = []
    level_list = LEVELS if args.all else [args.level]

    for level in level_list:
        chosen = select_words(words, level, args.limit)
        if not chosen:
            print(f"  [{level}] 没有词条，跳过")
            continue
        title = f"JLPT {level} 词读音"
        if args.limit:
            title += f"（试跑 {len(chosen)} 条）"
        packs.append(
            await build_pack(
                chosen,
                pack_id=level.lower() if level else "all",
                title=title,
                voice=args.voice,
                rate=args.rate,
                concurrency=args.concurrency,
                out_dir=args.out,
            )
        )

    catalog = {
        "version": 1,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "voice": args.voice,
        "packs": packs,
    }
    # 合并进已有目录：分几次跑 N5 / N4 时不能把前一次的卷冲掉
    catalog_path = os.path.join(args.out, "catalog.json")
    merged: dict[str, dict] = {}
    if os.path.exists(catalog_path):
        try:
            with open(catalog_path, encoding="utf-8") as f:
                for item in json.load(f).get("packs", []):
                    if item.get("id"):
                        merged[item["id"]] = item
        except Exception:  # noqa: BLE001 - 旧目录坏了就当没有
            merged = {}
    for item in packs:
        merged[item["id"]] = item

    order = {level.lower(): i for i, level in enumerate(LEVELS)}
    ordered = sorted(merged.values(), key=lambda p: order.get(p["id"], 99))

    catalog = {
        "version": 1,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "voice": args.voice,
        "packs": ordered,
    }
    with open(catalog_path, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)
    print(f"\n目录清单：{catalog_path}（共 {len(ordered)} 卷）")
    print("把 catalog.json 和各个 .voicepack 放到同一个可访问的地址下，App 里填这个地址就能装。")


if __name__ == "__main__":
    asyncio.run(main())
