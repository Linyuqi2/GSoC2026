#!/usr/bin/env bash
# Wrapper: invoke verify_phase4_trace.py from any working directory
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${HERE}/verify_phase4_trace.py" "$@"
