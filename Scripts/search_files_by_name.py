#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""递归搜索指定目录下文件名包含目标字符串的文件。"""

from __future__ import annotations

import argparse
from pathlib import Path


def find_matching_files(root_dir: Path, keyword: str) -> list[Path]:
    matches: list[Path] = []

    for path in root_dir.rglob("*"):
        if path.is_file() and keyword in path.name:
            matches.append(path.relative_to(root_dir))

    return sorted(matches)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="递归搜索目录下文件名中包含指定字符串的文件。"
    )
    parser.add_argument("directory", help="要搜索的根目录")
    parser.add_argument("keyword", help="要匹配的字符串")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root_dir = Path(args.directory).resolve()

    if not root_dir.exists():
        print(f"错误：目录不存在: {root_dir}")
        return 1

    if not root_dir.is_dir():
        print(f"错误：输入路径不是目录: {root_dir}")
        return 1

    matches = find_matching_files(root_dir, args.keyword)

    if matches:
        for relative_path in matches:
            print(relative_path.as_posix())
    else:
        print("未找到匹配文件。")

    print(f"文件总数: {len(matches)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())