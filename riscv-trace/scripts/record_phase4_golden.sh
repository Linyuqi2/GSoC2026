#!/usr/bin/env bash
# 将一次 cosim 生成的 trace 复制为仓库内 golden（默认：minimal hello_world 用例）。
# 用法：record_phase4_golden.sh TRACE.bin [DEST.bin]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RISCV_TRACE_ROOT="$(cd "${HERE}/.." && pwd)"
SRC="${1:?用法: $0 TRACE.bin [DEST.bin]}"
DEST="${2:-${RISCV_TRACE_ROOT}/golden/black-parrot-minimal-hello_world.trace.bin}"
if [[ ! -f "$SRC" ]]; then
  echo "record_phase4_golden: 源文件不存在: $SRC" >&2
  exit 1
fi
mkdir -p "$(dirname "$DEST")"
cp -f "$SRC" "$DEST"
echo "record_phase4_golden: 已写入 $(wc -c < "$DEST") 字节 -> $DEST"
