#!/usr/bin/env bash
# 在不跑完整 make prep / 不 sudo apt 的前提下，为 black-parrot-minimal cosim 准备 zynq-parrot/riscv 下的
# bootrom.none.riscv 与 hello_world.riscv（后者暂用上游 bp_tethered demo.riscv，便于链路打通）。
set -euo pipefail

GSOC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZP="${GSOC_ROOT}/zynq-parrot"
DEB_DIR="${ZP}/work/host-riscv-gcc"
PATH_GCC="${DEB_DIR}/usr/bin"
BOOTROM_DIR="${ZP}/import/black-parrot-sdk/bootrom"
RISCV_OUT="${ZP}/riscv"
DEMO="${ZP}/import/black-parrot/bp_top/test/tb/bp_tethered/demo.riscv"

if [[ ! -d "$ZP" ]]; then
  echo "错误: 未找到 $ZP" >&2
  exit 1
fi

mkdir -p "$RISCV_OUT" "$DEB_DIR"
cd "$DEB_DIR"
if [[ ! -x "${PATH_GCC}/riscv64-unknown-elf-gcc" ]]; then
  echo "正在下载并解压 Ubuntu 的 riscv64-unknown-elf 工具链（无需 sudo）..."
  apt-get download gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
  for f in *.deb; do
    [[ -f "$f" ]] || continue
    dpkg-deb -x "$f" .
  done
fi
export PATH="${PATH_GCC}:$PATH"
command -v riscv64-unknown-elf-gcc >/dev/null

echo "编译 bootrom.none.riscv ..."
make -C "$BOOTROM_DIR" clean bootrom.none.riscv CROSS_COMPILE=riscv64-unknown-elf-

cp -f "${BOOTROM_DIR}/bootrom.none.riscv" "${RISCV_OUT}/"
if [[ -f "$DEMO" ]]; then
  cp -f "$DEMO" "${RISCV_OUT}/hello_world.riscv"
  echo "已复制 demo.riscv -> ${RISCV_OUT}/hello_world.riscv（占位；正式开发可改为 SDK prog_lite 构建的 hello_world）。"
else
  echo "警告: 未找到 $DEMO，请检查 black-parrot 子模块。" >&2
  exit 1
fi

echo "完成: ${RISCV_OUT}/bootrom.none.riscv 与 hello_world.riscv 已就绪。"
