#!/usr/bin/env bash
# Copy a cosim trace output as the in-repo golden reference.
# Usage: record_phase4_golden.sh TRACE.bin [DEST.bin]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RISCV_TRACE_ROOT="$(cd "${HERE}/.." && pwd)"
SRC="${1:?Usage: $0 TRACE.bin [DEST.bin]}"
DEST="${2:-${RISCV_TRACE_ROOT}/golden/black-parrot-minimal-hello_world.trace.bin}"
if [[ ! -f "$SRC" ]]; then
  echo "record_phase4_golden: source file not found: $SRC" >&2
  exit 1
fi
mkdir -p "$(dirname "$DEST")"
cp -f "$SRC" "$DEST"
echo "record_phase4_golden: wrote $(wc -c < "$DEST") bytes -> $DEST"
