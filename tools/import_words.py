#!/usr/bin/env python3
"""把外部词表合并进 JianRiJi/Resources/seed_words.json。

用法：
    python3 tools/import_words.py --input my_words.csv --book "初级上"
    python3 tools/import_words.py --input jlpt_n3.tsv --book "中级" --dry-run
    python3 tools/import_words.py --input fix.csv --update      # 覆盖已存在的词

CSV/TSV 第一行是表头，支持的列（大小写不敏感）：
    term, reading, romaji, meaning, pos, jlpt, book, example, example_zh,
    example_furigana, note, tags

必填：term, reading, meaning
可选：其余；tags 用分号分隔，如「日常;食物」

规则：
- 以 term + reading 判重，已存在则跳过（除非 --update）
- 新 id 用 import-000001 起，避开现有词（仓库现有 id 是 egg-<uuid> 形）
- 没有 book 列的词不写 book 字段，App 里按 jlpt 兜底（N5→初级上 / N4→初级下 /
  N3→中级 / 其他→高级）；不要给 book 设默认值，否则会把高级别词误归到初级上
- 写回前校验 JSON 可解析，失败则不动原文件

注意：不要把商业教材的词表直接拷进公开仓库分发（见 docs/DATA.md）。
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEED = ROOT / "JianRiJi" / "Resources" / "seed_words.json"

FIELDS = {
    "term": "term",
    "reading": "reading",
    "romaji": "romaji",
    "meaning": "meaning",
    "pos": "pos",
    "part_of_speech": "pos",
    "jlpt": "jlpt",
    "book": "book",
    "example": "example",
    "example_zh": "example_zh",
    "example_furigana": "example_furigana",
    "note": "note",
    "tags": "tags",
}


def read_rows(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8-sig")
    delimiter = "\t" if path.suffix.lower() in {".tsv", ".tab"} else ","
    reader = csv.DictReader(text.splitlines(), delimiter=delimiter)
    rows = []
    for raw in reader:
        item = {}
        for key, value in raw.items():
            if key is None or value is None:
                continue
            field = FIELDS.get(key.strip().lower())
            if field is None:
                continue
            value = value.strip()
            if field == "tags":
                item[field] = [t.strip() for t in value.split(";") if t.strip()]
            else:
                item[field] = value
        if item.get("term") and item.get("reading") and item.get("meaning"):
            rows.append(item)
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--book", default=None, help="统一写入的词书名，如 初级上")
    parser.add_argument("--jlpt", default=None, help="统一写入的级别，如 N5")
    parser.add_argument("--update", action="store_true", help="已存在的词覆盖字段")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not SEED.exists():
        print(f"找不到 {SEED}", file=sys.stderr)
        return 1
    if not args.input.exists():
        print(f"找不到 {args.input}", file=sys.stderr)
        return 1

    words = json.loads(SEED.read_text(encoding="utf-8"))
    index = {(w["term"], w["reading"]): w for w in words}
    incoming = read_rows(args.input)

    added = updated = skipped = 0
    next_id = 1
    used_ids = {w["id"] for w in words}

    for row in incoming:
        if args.book:
            row["book"] = args.book
        if args.jlpt:
            row["jlpt"] = args.jlpt
        row.setdefault("pos", "名词")
        row.setdefault("jlpt", "N5")
        # 注意：这里故意不给 book 默认值。缺 book 的词由 App 按 jlpt 兜底；
        # 一旦写死默认值，高级别词会被误归到初级上。

        key = (row["term"], row["reading"])
        if key in index:
            if args.update:
                index[key].update({k: v for k, v in row.items() if v})
                updated += 1
            else:
                skipped += 1
            continue

        while f"import-{next_id:06d}" in used_ids:
            next_id += 1
        row["id"] = f"import-{next_id:06d}"
        used_ids.add(row["id"])
        next_id += 1
        words.append(row)
        index[key] = row
        added += 1

    print(f"读取 {len(incoming)} 行 · 新增 {added} · 更新 {updated} · 跳过重复 {skipped}")
    print(f"合并后共 {len(words)} 词")

    if args.dry_run:
        return 0

    payload = json.dumps(words, ensure_ascii=False, indent=2)
    json.loads(payload)  # 自校验
    SEED.write_text(payload + "\n", encoding="utf-8")
    print(f"已写入 {SEED}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
