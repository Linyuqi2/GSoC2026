#!/usr/bin/env python3
"""
Phase 4 初步验证：trace bin 存在、可选非空、严格帧解析、可选最少消息数、可选 golden 逐字节比对。

用法示例：
  python3 verify_phase4_trace.py bp_riscv_trace.bin --min-messages 1
  python3 verify_phase4_trace.py trace.bin --golden golden/hello_world.trace.bin
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

# 与 parse 脚本同目录，支持直接运行本文件
_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from parse_bp_riscv_trace import iter_messages_strict  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("bin", type=Path, help="仿真生成的 trace 二进制（如 bp_riscv_trace.bin）")
    ap.add_argument(
        "--vaddr-bits",
        type=int,
        default=39,
        help="虚址位宽（与 BlackParrot unicore 默认一致）",
    )
    ap.add_argument(
        "--min-messages",
        type=int,
        default=0,
        help="解析后消息条数下限，不满足则退出码 2",
    )
    ap.add_argument(
        "--allow-empty",
        action="store_true",
        help="允许 0 字节文件（默认不允许）",
    )
    ap.add_argument(
        "--golden",
        type=Path,
        default=None,
        help="可选：与之逐字节完全一致则通过",
    )
    ap.add_argument("-q", "--quiet", action="store_true", help="仅错误时打印")
    args = ap.parse_args()

    bin_path = args.bin
    if not bin_path.is_file():
        print(f"verify_phase4_trace: 文件不存在: {bin_path}", file=sys.stderr)
        return 1

    raw = bin_path.read_bytes()
    if len(raw) == 0 and not args.allow_empty:
        print("verify_phase4_trace: trace 为空（使用 --allow-empty 可放行）", file=sys.stderr)
        return 1

    if args.golden is not None:
        if not args.golden.is_file():
            print(f"verify_phase4_trace: golden 不存在: {args.golden}", file=sys.stderr)
            return 1
        gold = args.golden.read_bytes()
        if raw != gold:
            print(
                f"verify_phase4_trace: 与 golden 不一致（长度 {len(raw)} vs {len(gold)}）",
                file=sys.stderr,
            )
            return 1
        if not args.quiet:
            print("verify_phase4_trace: golden 字节比对 OK")

    try:
        msgs = list(iter_messages_strict(raw, args.vaddr_bits))
    except ValueError as e:
        print(f"verify_phase4_trace: 解析失败: {e}", file=sys.stderr)
        return 1

    if args.min_messages > 0 and len(msgs) < args.min_messages:
        print(
            f"verify_phase4_trace: 消息数 {len(msgs)} < --min-messages {args.min_messages}",
            file=sys.stderr,
        )
        return 2

    if not args.quiet:
        print(f"verify_phase4_trace: OK, {len(msgs)} message(s), {len(raw)} byte(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
