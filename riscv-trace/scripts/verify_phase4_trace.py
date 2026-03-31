from __future__ import annotations

import argparse
import sys
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from parse_bp_riscv_trace import iter_messages_strict  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("bin", type=Path, help="trace binary from cosim (e.g. bp_riscv_trace.bin)")
    ap.add_argument(
        "--vaddr-bits",
        type=int,
        default=39,
        help="virtual address width (BlackParrot unicore default 39)",
    )
    ap.add_argument(
        "--min-messages",
        type=int,
        default=0,
        help="minimum message count; exit code 2 if not met",
    )
    ap.add_argument(
        "--allow-empty",
        action="store_true",
        help="allow empty (0-byte) trace file",
    )
    ap.add_argument(
        "--golden",
        type=Path,
        default=None,
        help="optional golden reference for byte-exact comparison",
    )
    ap.add_argument("-q", "--quiet", action="store_true", help="仅错误时打印")
    args = ap.parse_args()

    bin_path = args.bin
    if not bin_path.is_file():
        print(f"verify_phase4_trace: file not found: {bin_path}", file=sys.stderr)
        return 1

    raw = bin_path.read_bytes()
    if len(raw) == 0 and not args.allow_empty:
        print("verify_phase4_trace: trace is empty (use --allow-empty to allow)", file=sys.stderr)
        return 1

    if args.golden is not None:
        if not args.golden.is_file():
            print(f"verify_phase4_trace: golden not found: {args.golden}", file=sys.stderr)
            return 1
        gold = args.golden.read_bytes()
        if raw != gold:
            print(
                f"verify_phase4_trace: mismatch with golden ({len(raw)} vs {len(gold)} bytes)",
                file=sys.stderr,
            )
            return 1
        if not args.quiet:
            print("verify_phase4_trace: golden byte-exact match OK")

    try:
        msgs = list(iter_messages_strict(raw, args.vaddr_bits))
    except ValueError as e:
        print(f"verify_phase4_trace: parse error: {e}", file=sys.stderr)
        return 1

    if args.min_messages > 0 and len(msgs) < args.min_messages:
        print(
            f"verify_phase4_trace: message count {len(msgs)} < --min-messages {args.min_messages}",
            file=sys.stderr,
        )
        return 2

    if not args.quiet:
        print(f"verify_phase4_trace: OK, {len(msgs)} message(s), {len(raw)} byte(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
