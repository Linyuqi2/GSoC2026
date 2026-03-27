# ZynqParrot RISC-V Tracer — 实施计划

## 项目目标

在 ZynqParrot 中设计并集成符合 [RISC-V Trace 规范](https://github.com/riscv-non-isa/riscv-trace-spec) 的 Trace 实现，包括：

- **基础设施说明（proposal / mentor）**：ZynqParrot cosim 层次与框图 → [docs/ZYNQPARROT_INFRASTRUCTURE.md](docs/ZYNQPARROT_INFRASTRUCTURE.md)
- **RTL**：SystemVerilog 实现与仿真/测试
- **FPGA 集成**：Vivado IPI Block Diagram 设计
- **软件**：C++ 驱动，支持 **Co-Simulation**（Verilator/VCS）与 **Co-Emulation**（Zynq PS）

---

## 阶段与工作顺序

### Phase 1：阅读 RISC-V Trace 规范并确定实现子集  
**状态**：已完成  
**产出**：规范摘要、选定格式（如 N-Trace 最小集）、与 BlackParrot 的对应关系说明

- 阅读 [riscv-non-isa/riscv-trace-spec](https://github.com/riscv-non-isa/riscv-trace-spec) 与 [tg-nexus-trace RISC-V-N-Trace.adoc](https://github.com/riscv-non-isa/tg-nexus-trace/blob/main/docs/RISC-V-N-Trace.adoc)
- 确定采用的 trace 格式与消息类型（如 Instruction trace、DirectBranch、IndirectBranch 等）
- 明确“最小可交付”范围，便于 175 小时内完成

**Phase 1 详细摘要与决策建议** → 见 [docs/PHASE1_TRACE_SPEC_AND_DECISIONS.md](docs/PHASE1_TRACE_SPEC_AND_DECISIONS.md)

---

### Phase 2：在 BlackParrot 上定义 Trace 接口  
**状态**：已完成  
**产出**：Trace 接口定义（信号列表、位宽、时序）、与 core commit 的接线点

- 从 `bp_be_nonsynth_cosim` / commit 边界确定可用的 PC、指令、提交类型等信号
- 定义 Trace Encoder 的输入接口（valid、pc、insn、exception 等）
- 确定单核优先还是预留多核

**Phase 2 接口规格** → 见 [docs/PHASE2_TRACE_INTERFACE_SPEC.md](docs/PHASE2_TRACE_INTERFACE_SPEC.md)（最简/最通用方案）

---

### Phase 3：实现 Trace Encoder（+ 可选 Buffer）  
**状态**：RTL 已完成（含 Phase 4 在 encoder 内加入 discontinuity 事件 FIFO；cosim 验证见 Phase 4）  
**产出**：SystemVerilog 模块、符合 spec 的编码流输出

- 实现 Trace Encoder 模块，输入为 Phase 2 的接口
- 输出为 RISC-V trace 编码流（或选定子集）
- 可选：PL 内 FIFO/SRAM 作为 buffer，经 AXI 或 AXI-Stream 输出

**Phase 3 RTL 与帧格式说明** → 见 [docs/PHASE3_RTL_DESIGN.md](docs/PHASE3_RTL_DESIGN.md)；源码在 `riscv-trace/v/`。

---

### Phase 4：Verilator/VCS 仿真与 Trace 解析/比对测试  
**状态**：基本完成（encoder 事件 FIFO 降低 overflow、minimal cosim 下 trace 规模正常；仓库内字节级 golden + 录制脚本；ISA 参考模型比对可后续加）  
**产出**：仿真通过、trace 解析脚本/工具、与 golden 比对方法

- 在现有 bp_tethered / ZynqParrot cosim 下跑固定程序并抓 trace → 已实现：`black-parrot-minimal-example` 中 `bp_riscv_trace_top` + `bp_riscv_trace_dpi_sink`，见 [docs/PHASE4_COSIM.md](docs/PHASE4_COSIM.md)
- 编写 trace 解析（C++ 或 Python），与 Dromajo/Spike 或自研 golden 比对 → 已实现：`riscv-trace/scripts/parse_bp_riscv_trace.py`；**字节级 golden**：`riscv-trace/golden/black-parrot-minimal-hello_world.trace.bin` + `scripts/record_phase4_golden.sh`；与 Spike/Dromajo 的指令级自动比对留作下一步

---

### Phase 5：Block Diagram 集成（Vivado IPI）  
**状态**：待开始  
**产出**：`axi_trace_bd.tcl`、Trace IP 在 BD 中的连接

- 新增 `cosim/tcl/bd/axi_trace_bd.tcl`
- 在 BD 中连接 AXI、时钟、复位；地址与现有 GP0/GP1 规划一致

---

### Phase 6：在 black-parrot-example 中集成 Trace IP  
**状态**：待开始  
**产出**：top_zynq 中实例化 Trace、vivado-build-ip.tcl 调用 axi_trace_bd

- 在 `black-parrot-example` 的 `top_zynq.sv` 中实例化 Trace 模块并连接 core 的 trace 接口
- 在 `vivado-build-ip.tcl` 中加入对 `axi_trace_bd.tcl` 的调用

---

### Phase 7：C++ 驱动（Co-Sim + Co-Emulation）  
**状态**：待开始  
**产出**：同一套 API 在 Co-Sim 与 Co-Emulation 下可用的 Trace 驱动

- 通过 AXI 访问 Trace CSR（使能、buffer 基址、启动/停止等）
- 提供读取 trace buffer / 流并写文件的接口
- 保证 Verilator/VCS 与 Zynq PS 共用同一套寄存器布局与 API

---

### Phase 8：Before/After 框图与文档  
**状态**：待开始  
**产出**：集成前后框图、proposal/文档更新

- 绘制集成前（无 Trace）与集成后（含 Trace IP）的 Block Diagram
- 更新 README / 设计文档，便于 GSoC proposal 与后续维护

---

## 参考位置速查

| 内容           | 路径 |
|----------------|------|
| ZynqParrot 总览 | `zynq-parrot/README.md` |
| Cosim 示例     | `zynq-parrot/cosim/README.md` |
| Shell RTL      | `zynq-parrot/cosim/v/bsg_zynq_pl_shell.sv` |
| BD 示例        | `zynq-parrot/cosim/tcl/bd/axi_debug_bd.tcl` |
| C++ PL API     | `zynq-parrot/cosim/include/common/bsg_zynq_pl_base.h` |
| BlackParrot cosim 信号 | `black-parrot/bp_be/test/common/bp_be_nonsynth_cosim.sv` |
| 已有 tracer 风格 | `black-parrot/bp_me/test/common/bp_me_nonsynth_*_tracer.sv` |

---

*计划创建日期：2026-03-15*
