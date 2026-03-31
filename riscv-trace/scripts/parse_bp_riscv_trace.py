from __future__ import annotations

import argparse
import json
import sys
from typing import Iterator


def iter_messages(data: bytes, vaddr_bits: int) -> Iterator[dict]:
    npc_chunks = (vaddr_bits + 5) // 6
    msg_len = 3 + npc_chunks
    i = 0
    n = len(data)
    while i + msg_len <= n:
        b0, b1, b2 = data[i], data[i + 1], data[i + 2]
        if (b0 & 3) != 0 or ((b0 >> 2) & 0x3F) != 0x04:
            i += 1
            continue
        itype = (b1 >> 2) & 7
        icnt6 = (b2 >> 2) & 0x3F
        npc = 0
        for k in range(npc_chunks):
            b = data[i + 3 + k]
            mdo = (b >> 2) & 0x3F
            mseo = b & 3
            npc |= mdo << (6 * k)
            if k == npc_chunks - 1:
                if mseo != 3:
                    raise ValueError(
                        f"expected MSEO=3 on last npc byte at index {i + 3 + k}, got {mseo}"
                    )
            elif mseo != 0:
                raise ValueError(f"unexpected MSEO={mseo} on npc byte {k}")
        yield {"itype": itype, "icnt6": icnt6, "npc": npc}
        i += msg_len


def iter_messages_strict(data: bytes, vaddr_bits: int) -> Iterator[dict]:
    """Parse from offset 0 with no leading garbage or trailing bytes allowed."""
    npc_chunks = (vaddr_bits + 5) // 6
    msg_len = 3 + npc_chunks
    i = 0
    n = len(data)
    while i < n:
        if i + msg_len > n:
            raise ValueError(
                f"trailing incomplete frame at offset {i}: need {msg_len} bytes, have {n - i}"
            )
        b0, b1, b2 = data[i], data[i + 1], data[i + 2]
        if (b0 & 3) != 0 or ((b0 >> 2) & 0x3F) != 0x04:
            raise ValueError(f"bad message header at offset {i}: 0x{b0:02x}")
        itype = (b1 >> 2) & 7
        icnt6 = (b2 >> 2) & 0x3F
        npc = 0
        for k in range(npc_chunks):
            b = data[i + 3 + k]
            mdo = (b >> 2) & 0x3F
            mseo = b & 3
            npc |= mdo << (6 * k)
            if k == npc_chunks - 1:
                if mseo != 3:
                    raise ValueError(
                        f"expected MSEO=3 on last npc byte at index {i + 3 + k}, got {mseo}"
                    )
            elif mseo != 0:
                raise ValueError(f"unexpected MSEO={mseo} on npc byte {k}")
        yield {"itype": itype, "icnt6": icnt6, "npc": npc}
        i += msg_len


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("bin", help="bp_riscv_trace.bin (raw bytes from cosim)")
    ap.add_argument(
        "--vaddr-bits",
        type=int,
        default=39,
        help="virtual address width (BlackParrot unicore default 39)",
    )
    ap.add_argument("--jsonl", action="store_true", help="print one JSON object per line")
    ap.add_argument(
        "--strict",
        action="store_true",
        help="no leading garbage / no trailing bytes; fail on any framing error",
    )
    args = ap.parse_args()
    try:
        data = open(args.bin, "rb").read()
    except FileNotFoundError:
        print(
            "parse_bp_riscv_trace: file not found: {!r}\n"
            "  Trace is only produced by the black-parrot-minimal-example cosim via DPI."
            .format(args.bin),
            file=sys.stderr,
        )
        return 1
    it = iter_messages_strict(data, args.vaddr_bits) if args.strict else iter_messages(
        data, args.vaddr_bits
    )
    msgs = list(it)
    if args.jsonl:
        for m in msgs:
            print(json.dumps(m))
    else:
        print(f"messages: {len(msgs)}")
        for idx, m in enumerate(msgs):
            print(f"  [{idx}] itype={m['itype']} icnt6={m['icnt6']} npc=0x{m['npc']:x}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
