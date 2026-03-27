# Phase 2：Trace 接口规格（最简 / 最通用方案）

本文档在 **Phase 1 最简、最通用方案** 下，定义 RISC-V Trace 在 ZynqParrot/BlackParrot 上的接口与接线点，供 Phase 3 RTL 实现与 Phase 6 集成使用。

---

## 一、Phase 1 方案固化（本阶段前提）

| 项目 | 选择 |
|------|------|
| 格式 | 简化 N-Trace：DirectBranch(3)、IndirectBranch(4)、ProgTraceSync(9)，固定字段、最小 MSEO |
| 模式 | BTM |
| itype | 3-bit，由 Ingress Adapter 从 commit_pkt + instr 推导 |
| 输出 | 8-bit 流 + valid；Co-Sim 写文件，FPGA 接 AXI-Stream/FIFO |
| 核数 | 单核，无 SRC 字段 |
| Control | AXI-Lite：enable + mode(BTM) 两个 CSR |

---

## 二、模块层次与数据流

```
BlackParrot BE (calculator)
    │ commit_pkt_o, trans_info_o, decode_info_o, comp_stage_r[2]
    ▼
┌─────────────────────────┐
│  bp_riscv_trace_ingress  │  从 commit + instr 推导 itype、i_cnt
│  (Ingress Adapter)       │  输出：标准 N-Trace 入端口
└────────────┬────────────┘
             │ valid, pc, npc, itype[2:0], i_cnt
             ▼
┌─────────────────────────┐
│  bp_riscv_trace_encoder  │  BTM 编码，MSEO+MDO 字节流
│  (N-Trace Encoder)       │
└────────────┬────────────┘
             │ trace_data_o[7:0], trace_v_o
             ▼
       FIFO / 文件 / AXI-Stream
```

- **Ingress Adapter**：仅组合逻辑 + 少量状态（如 I-CNT 累计），不改变 BlackParrot 行为。
- **Encoder**：同步逻辑，输出 8-bit 流；下游在 Co-Sim 可 `$fwrite`，在 FPGA 接 FIFO。

---

## 三、接口 1：BlackParrot → Ingress Adapter

从 BlackParrot Back End 接入的**只读**信号，与 `bp_be_nonsynth_cosim` 同源，便于在 testbench 或 top_zynq 中与 cosim 并列挂接。

### 3.1 接线层级

- **推荐**：在 **testbench / top 层** 从 `calculator`（即 `bp_be_calculator` 实例）取信号，不修改 `bp_be` 内部 RTL。
- **路径**：与 cosim 一致，例如  
  `dut.core.xxx.calculator.commit_pkt_o`（具体层次以实际 top 为准，见 Phase 6）。

### 3.2 信号列表（Ingress Adapter 输入）

所有信号与 core 同频同拍；无 valid 握手，由 `commit_pkt.instret | commit_pkt.exception | commit_pkt._interrupt` 表示“本拍有提交”。

| 信号名 | 方向 | 位宽 | 来源 | 说明 |
|--------|------|------|------|------|
| `clk_i` | I | 1 | 与 core 同 clk | 与 calculator 同时钟 |
| `reset_i` | I | 1 | 与 core 同 reset | 同步复位 |
| `commit_pkt_i` | I | `commit_pkt_width_lp` | `calculator.commit_pkt_o` | `bp_be_commit_pkt_s` |
| `trans_info_i` | I | `trans_info_width_lp` | `calculator.trans_info_o` | `bp_be_trans_info_s`（可选，用于过滤/ownership） |
| `decode_info_i` | I | `decode_info_width_lp` | `calculator.decode_info_o` | `bp_be_decode_info_s`（可选，如 debug_mode 关 trace） |
| `comp_pkt_i` | I | `wb_pkt_width_lp` | `calculator.comp_stage_r[2]` | 写回包（用于 rd 等，最小实现可不用） |

**最小实现**：仅使用 `commit_pkt_i`（含 `pc`、`npc`、`instr`、`instret`、`exception`、`_interrupt`、`eret`、`count`、`size`）即可推导 itype 并驱动 Encoder；`trans_info_i` / `decode_info_i` 可用于“debug 模式不 trace”等简单过滤。

### 3.3 位宽与参数（与 BP 一致）

由 `bp_params_p` 及 `declare_bp_proc_params` / `declare_bp_be_if_widths` 得到，例如：

- `vaddr_width_p`：39（默认）
- `paddr_width_p`：56（默认）
- `instr_width_gp`：32
- `fetch_ptr_p`、`issue_ptr_p`：由 aviary 定义（如 fetch_ptr_p=2, issue_ptr_p=2）
- `commit_pkt_width_lp`、`trans_info_width_lp`、`decode_info_width_lp`、`wb_pkt_width_lp`：见 `bp_be_defines.svh`

Ingress Adapter 模块建议使用与 `bp_be` 相同的参数宏，以便直接接 `commit_pkt_o` 等。

---

## 四、接口 2：Ingress Adapter → Encoder（N-Trace 标准入端口）

Adapter 输出符合 N-Trace/E-Trace 规定的**单拍** Instruction Trace Ingress 信号，便于 Encoder 只实现标准行为。

### 4.1 信号列表（Encoder 输入）

| 信号名 | 方向 | 位宽 | 说明 |
|--------|------|------|------|
| `clk_i` | I   | 1 |   与 core 同频 |
| `reset_i` | I | 1 |   同步复位 |
| `enable_i` | I | 1 |  来自 Trace Control CSR，0 时 Encoder 不产生输出 |
| `valid_i` | I | 1 |   本拍有退休/异常/中断，等价于 instret \| exception \| _interrupt |
| `pc_i` | I  | `vaddr_width_p` | 当前退休指令 PC（或异常/中断时当前 PC） |
| `npc_i` | I | `vaddr_width_p` | 下一 PC（跳转/异常/中断目标） |
| `itype_i` | I | 3 | N-Trace itype：0=顺序，1=Exception，2=Interrupt，3=Trap return，4=Not-taken branch，5=Taken branch，6=Indirect jump |
| `i_cnt_i` | I | I-CNT 位宽（见下） | 本拍退休的 16-bit 指令单元数（RV32 一般为 1 或 2） |

**I-CNT 位宽**：N-Trace 允许变长，最小实现可固定为 **2 bit**（取值 1 或 2），即每拍 1 或 2 个 16-bit 单元；若与 BP 的 `count`/`size` 一致，可用 `fetch_ptr_p` 或 2 的幂宽度。

### 4.2 itype 推导规则（Ingress Adapter 内）

仅用 `commit_pkt_i` 与 `instr` 时，建议映射如下（最简、最通用）：

| 条件 | itype |
|------|-------|
| `exception` | 1 |
| `_interrupt` | 2 |
| `eret` | 3 |
| 从 `instr` 判 B-type 且 not-taken（npc == pc+4） | 4 |
| 从 `instr` 判 B-type 且 taken（npc != pc+4） | 5 |
| JALR / 其他间接跳转（从 opcode + npc != pc+4） | 6 |
| 其他（顺序） | 0 |

B-type：opcode == 7'b1100011；JALR：opcode == 7'b1100111。不区分子类型（如 call/return）时，6 已足够。

---

## 五、接口 3：Encoder → 下游（8-bit 流）

Encoder 输出供 Co-Sim 写文件或 FPGA FIFO/AXI-Stream 使用。

### 5.1 信号列表

| 信号名 | 方向 | 位宽 | 说明 |
|--------|------|------|------|
| `clk_i` | I | 1 | 与 core 同频 |
| `trace_data_o` | O | 8 | N-Trace 字节：MSEO[1:0] + MDO[5:0]，LSB first |
| `trace_v_o` | O | 1 | 1 表示本拍 `trace_data_o` 有效（非 idle 时可拉高多拍） |

可选（便于测试）：

- `trace_last_o`：当前字节为某条消息的最后一个字节（MSEO=11），可省略，由解码器按 MSEO 判断。

### 5.2 时序

- 与 core 同时钟；`trace_v_o` 与 `trace_data_o` 在 `clk_i` 上升沿有效。
- 无背压：下游 FIFO 满时由上层逻辑（或 Trace Control）通过 `enable_i` 停 trace，或 FIFO 深度足够大。

---

## 六、Trace Control（AXI-Lite 寄存器，Phase 3/7 实现）

最简两个 CSR，位宽与 ZynqParrot shell 一致（32-bit）：

| 偏移 | 名称 | 位 | 说明 |
|------|------|----|------|
| 0x0 | enable | 0 | 1=开启 trace，0=关闭 |
| 0x0 | mode | 1 | 0=BTM（当前仅支持 BTM） |
| 0x4 | (保留) | - | 可选：buffer 基址、溢出状态等 |

`enable` 接 Ingress Adapter 或 Encoder 的 `enable_i`；`mode` 预留。

---

## 七、接线点汇总（与 BlackParrot / ZynqParrot 的衔接）

### 7.1 在仿真 testbench（如 bp_tethered）中

- 在 **同一 testbench** 中与 `bp_be_nonsynth_cosim` 类似，通过 **bind** 或显式实例化挂到 `calculator` 所在层次。
- 推荐：**显式实例化** 在 testbench 内，输入接：
  - `commit_pkt_i` ← `calculator.commit_pkt_o`
  - `trans_info_i` ← `calculator.trans_info_o`
  - `decode_info_i` ← `calculator.decode_info_o`
  - `comp_pkt_i` ← `calculator.comp_stage_r[2]`
- 输出 `trace_data_o`、`trace_v_o` 可接：
  - 仿真：`$fwrite` 到 trace 文件；
  - 或 DPI-C 传给 C++ 做在线解析（Phase 4）。

### 7.2 在 ZynqParrot top_zynq（black-parrot-example）中

- **top_zynq** 内已有 BlackParrot 核（dut）及 shell；Trace 作为**独立子模块**实例化。
- 从 **dut** 内部暴露到 top 的接口需在 Phase 6 确定（可选：在 top 中引用 `dut.xxx.calculator.commit_pkt_o` 等，或通过 hierarchy 参数传入）。
- Trace 输出接 **PL 内 FIFO**，FIFO 经 shell 的 AXI 或 FIFO 口被 PS 读取（与现有 axi_fifo_bd 模式一致）。

### 7.3 时钟与复位

- Trace 与 core **同 clk、同 reset**，避免跨时钟；在 top 中统一使用 `aclk`/`aresetn`（或 core 的 clk/reset）。

---

## 八、Phase 2 产出清单（自检）

- [x] 接口 1：BlackParrot → Ingress Adapter 的信号、位宽、来源层次
- [x] 接口 2：Ingress Adapter → Encoder 的 N-Trace 入端口（valid, pc, npc, itype, i_cnt）
- [x] 接口 3：Encoder → 8-bit 流（trace_data_o, trace_v_o）
- [x] itype 推导规则（3-bit 最简）
- [x] Trace Control 最小 CSR（enable, mode）
- [x] 接线点：testbench 与 top_zynq 的挂接思路

Phase 3 已实现 `riscv-trace/v/` 下 `bp_riscv_trace_ingress`、`bp_riscv_trace_encoder`、`bp_riscv_trace_top`；**简化帧**与完整 N-Trace 二进制差异见 [PHASE3_RTL_DESIGN.md](PHASE3_RTL_DESIGN.md)。
