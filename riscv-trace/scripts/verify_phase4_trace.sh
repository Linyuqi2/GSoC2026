#!/usr/bin/env bash
# 包装器：在任意 cwd 调用 verify_phase4_trace.py
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${HERE}/verify_phase4_trace.py" "$@"
