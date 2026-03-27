# RISC-V Trace（ZynqParrot / BlackParrot 子集）

本目录为 **GSoC 计划** 中的 RTL 子树，与上游 `black-parrot/` **松耦合**：不修改 BP 源码，通过 top/testbench 接线。

## 目录

- `v/` — SystemVerilog
  - `bp_riscv_trace_ingress.sv`
  - `bp_riscv_trace_encoder.sv`
  - `bp_riscv_trace_top.sv`
- `flist.vcs` — VCS 文件列表（相对本仓库根路径）

## 依赖

- BlackParrot 头文件：`bp_common_defines.svh`、`bp_be_defines.svh`（及 `BSG` 相关 include）
- 编译时增加例如（路径按本机 BP 根目录调整）：

```text
+incdir+$BLACK_PARROT/bp_common/src/include
+incdir+$BLACK_PARROT/bp_be/src/include
+incdir+$BLACK_PARROT/external/basejump_stl/bsg_misc
```

## 文档

- 接口与 itype 规则：`docs/PHASE2_TRACE_INTERFACE_SPEC.md`
- RTL 设计原因与帧格式：`docs/PHASE3_RTL_DESIGN.md`
- Phase 4 cosim 接线、落盘与解析：`docs/PHASE4_COSIM.md`
- Phase 4 验证：`scripts/verify_phase4_trace.py`（及 `verify_phase4_trace.sh`）；解析选项：`parse_bp_riscv_trace.py --strict`
- Phase 4 golden（minimal hello_world）：`golden/black-parrot-minimal-hello_world.trace.bin`；更新：`scripts/record_phase4_golden.sh`
