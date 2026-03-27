# Phase 1：RISC-V Trace 规范与实现决策

本文档是 Phase 1 的产出：规范要点摘要 + 实现子集与决策建议，供你选择方向。

---

## 一、RISC-V Trace 规范要点摘要

### 1.1 规范来源

- **RISC-V N-Trace (Nexus-based Trace) Specification** v1.0（已批准）
  - 仓库：<https://github.com/riscv-non-isa/tg-nexus-trace>，文档：`docs/RISC-V-N-Trace.adoc`
- **Trace Ingress Port** 与 E-Trace 共用：来自 *Efficient Trace for RISC-V* 的 **Instruction Trace Interface**
- **Trace Control**：*RISC-V Trace Control Interface Specification*（与 E-Trace 共用部分寄存器）

### 1.2 整体架构

```
RISC-V Hart → Trace Ingress Port → Trace Encoder → N-Trace 消息流 → 传输/存储
                   ↑                      ↑
            (每拍提交的信息)          (TCODE + 各消息类型)
```

- **Trace Ingress Port**：Hart 每拍提供给 Encoder 的信号（valid、PC、指令、**itype** 等）。
- **itype**：3-bit 或 4-bit，表示“本拍提交如何结束当前指令块”，用于 Encoder 决定发哪种消息：
  - 0 = No special type（顺序执行）
  - 1 = Exception
  - 2 = Interrupt
  - 3 = Trap return (MRET/SRET)
  - 4 = Not-taken branch
  - 5 = Taken branch
  - 6 = Indirect jump (JALR 等)
  - 8–15 = 扩展（Direct/Indirect call、return、jump 等，用于更好的压缩）

### 1.3 N-Trace 传输协议（简化）

- 每字节 = **MSEO[1:0]** + **MDO[5:0]**（共 8 bit）
- MSEO：00=消息开始/字段中，01=变长字段结束，11=消息结束或 idle（0xFF 表示 idle）
- 消息结构：**TCODE(6 bit)** [可选 SRC] [payload 字段…] [可选 TSTAMP]
- 比特/字节序：LSB first

### 1.4 两种指令 Trace 模式（至少实现一种）

| 模式 | 说明 |
|------|------|
| **BTM (Branch Trace Messaging)** | 仅对 **taken** 的直接条件分支发消息；可对重复分支做计数聚合（RepeatBranch） |
| **HTM (History Trace Messaging)** | 每个直接条件分支（taken/not-taken）在 **HIST** 里占 1 bit，压缩率更高 |

规范要求 Encoder **至少支持 BTM 或 HTM 之一**。

### 1.5 主要消息类型（与 BlackParrot 最相关的）

| TCODE | 消息 | 用途 |
|-------|------|------|
| 2 | Ownership | 源/能力声明 |
| 3 | **DirectBranch** | 顺序执行后的 I-CNT（+ 可选 F-ADDR） |
| 4 | **IndirectBranch** | 间接跳转/异常/中断：I-CNT + F-ADDR，B-TYPE 区分 jump/exception/interrupt |
| 8 | Error | 错误信息 |
| 9 | **ProgTraceSync** | 同步点（解码可从这里开始） |
| 11 | **DirectBranchSync** | 带 SYNC 的 DirectBranch |
| 12 | **IndirectBranchSync** | 带 SYNC 的 IndirectBranch |
| 28/29 | IndirectBranchHist / IndirectBranchHistSync | HTM 模式用 |
| 30 | **RepeatBranch** | BTM 下重复分支计数 |

最小可运行子集通常包括：**DirectBranch(3)**、**IndirectBranch(4)**、**ProgTraceSync(9)** 或 **DirectBranchSync(11)**，以及可选 **RepeatBranch(30)**。

---

## 二、BlackParrot 侧已有信号（可直接用于 Trace）

从 `bp_be_nonsynth_cosim.sv` 和 `bp_be_defines.svh` 可知，每拍提交时已有：

### 2.1 `bp_be_commit_pkt_s`（来自 `calculator.commit_pkt_o`）

| 字段 | 含义 | 对应 N-Trace / itype |
|------|------|----------------------|
| `pc` | 当前提交指令的 PC | F-ADDR / U-ADDR、I-CNT 的基准 |
| `npc` | 下一 PC | 异常/中断/跳转的目标地址 |
| `instr` | 32-bit 指令 | 解码器可用来验证；Encoder 通常不直接传 |
| `instret` | 指令成功退休 | 等价于 ingress port 的 valid |
| `exception` | 异常 | itype=1 (Exception) |
| `_interrupt` | 中断 | itype=2 (Interrupt) |
| `eret` | MRET/SRET | itype=3 (Trap return) |
| `count` / `size` | 本拍退休的 16-bit 单元数 | 用于 I-CNT 递增 |
| `priv_n`、`translation_en_n` 等 | 状态 | 可选用于 Ownership/Context |

此外还有：`itlb_miss`、`icache_miss`、`dtlb_*`、`dcache_*`、`fencei`、`sfence`、`csrw`、`wfi` 等，可用于区分“特殊类型”或仅用 exception/interrupt/eret 做最小实现。

### 2.2 `bp_be_trans_info_s`（如 `trans_info_lo.priv_mode`）

- 当前特权级等，可用于 Ownership 或过滤。

### 2.3 `bp_be_decode_info_s`（如 `decode_info_lo.debug_mode`）

- 可用于在 debug 模式下关闭或过滤 trace。

### 2.4 Cosim 已用的“等价”信号（可复用逻辑）

- `step_pc` = `commit_pkt_lo.pc`
- `step_insn` = `commit_pkt_lo.instr`
- `step_npc` = `commit_pkt_lo.npc`
- `step_priv_mode` = `trans_info_lo.priv_mode`
- trap：`commit_pkt_lo.exception` / `commit_pkt_lo._interrupt`，目标 `step_npc`

这些与 N-Trace 的 itype 和 IndirectBranch 目标地址完全对应。

---

## 三、决策建议（供你选择）

下面给出几类决策点和可选方案，便于你在 175 小时内做取舍。

### 决策 1：Trace 格式与规范符合度

| 选项 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| **A. 完整 N-Trace 子集** | 实现 BTM 或 HTM + 上述核心消息，严格按 N-Trace 编码（MSEO+MDO、TCODE、I-CNT、F-ADDR 等） | 与标准工具/解码器兼容，proposal 好看 | 工作量大，需仔细实现变长字段与 MSEO 状态机 |
| **B. 简化 N-Trace（推荐起步）** | 只实现 **DirectBranch(3)**、**IndirectBranch(4)**、**ProgTraceSync(9)**，固定字段长度、最小 MSEO | 快速出结果，仍可声称“N-Trace 兼容子集” | 压缩率不如完整版，工具链可能需要自写简单解码器 |
| **C. 自定义简单格式** | 每拍固定 8B/16B：PC + NPC + 类型（顺序/跳转/异常/中断） | 实现最快，C++ 解析极简 | 不符合 RISC-V 标准，proposal 需说明“为后续迁移 N-Trace 做铺垫” |

**建议**：先选 **B**，在文档中写明“Phase 1 最小 N-Trace 子集”，后续可扩展 BTM 的 RepeatBranch 或 HTM。

---

### 决策 2：BTM 还是 HTM

| 选项 | 描述 |
|------|------|
| **BTM** | 只对 taken branch 发 DirectBranch；可加 RepeatBranch 聚合循环。实现相对直观。 |
| **HTM** | 每个条件分支 1 bit 进 HIST，IndirectBranch 时带 HIST。压缩更好，但 Encoder 要维护 history buffer。 |

**建议**：第一版只做 **BTM**（含 DirectBranch + IndirectBranch），HTM 作为“可选扩展”写在文档里。

---

### 决策 3：itype 从哪里来

N-Trace 需要每拍一个 **itype**。BlackParrot 没有现成 itype 信号，需要从 `commit_pkt` + `instr` 推导：

- **exception / _interrupt** → itype 1 或 2
- **eret** → itype 3
- 从 **instr** 解码：B-type 分支 + 是否 taken（npc != pc+4）→ itype 4/5；JALR → itype 6；JAL → itype 0/9/11/15 等

**建议**：在 Trace Encoder 前加一个 **Ingress Adapter** 小模块：输入为 `commit_pkt` + `instr` + `npc`，输出为 N-Trace 规定的 valid + pc + itype（+ 可选 count）。这样 Encoder 严格按 spec 的 itype 表驱动，核心逻辑清晰。

---

### 决策 4：Trace 输出如何接到 ZynqParrot

| 选项 | 描述 | 适用场景 |
|------|------|----------|
| **AXI-Stream 到 FIFO** | Encoder 输出 8-bit 或 32-bit 流，经 FIFO 由 PS 通过 AXI 轮询或 DMA 读 | Co-Sim + Co-Emulation 统一，与现有 axi_fifo 模式一致 |
| **AXI-Lite 寄存器 + 内部 SRAM** | Encoder 写内部 buffer，PS 通过 AXI 读 buffer 窗口 | 实现简单，适合小 buffer、低带宽 |
| **仅仿真写文件** | 第一版只在 Verilator/VCS 里 `$fwrite` 到文件，不接 AXI | 最快验证编码正确性，后再接 AXI |

**建议**：先做 **“Encoder 输出到 8-bit 流”**；在 Co-Sim 里该流可写文件或进 DPI-C 给 C++ 解析；在 FPGA 上该流接 **AXI-Stream → FIFO**，再由现有 shell 的 FIFO 或 DMA 读到 PS（与 `axi_fifo_bd.tcl` 类似）。

---

### 决策 5：单核还是多核

- 当前 ZynqParrot black-parrot-example 多为 **单核**。
- N-Trace 的 **SRC** 字段可区分多 hart；单核时 SRC 可省略。

**建议**：**单核优先**，接口预留 `hart_id` 或 SRC 位宽，便于以后多核扩展。

---

### 决策 6：Trace Control 寄存器

- 规范有 trTeEnable、trTeInstTracing、trTeInstMode（3=BTM，6=HTM）等，通常在 **Trace Control Interface** 里通过调试/MMIO 访问。
- 在 ZynqParrot 上可简化为：**一个 AXI-Lite 从口**，实现 2–4 个 CSR：enable、mode(BTM/HTM)、可选 buffer 基址/大小；其他位暂时只读 0。

**建议**：第一版实现 **enable + mode** 即可，其余在文档中列为“后续按 Trace Control Spec 扩展”。

---

## 四、Phase 1 建议产出清单（自检）

- [ ] 确定采用的格式：**简化 N-Trace 子集（B）** 或 A/C
- [ ] 确定模式：**BTM**
- [ ] 确定 itype 来源：**Ingress Adapter** 从 `commit_pkt`+`instr` 推导
- [ ] 确定输出：**8-bit 流** → Co-Sim 写文件 / FPGA 接 AXI-Stream+FIFO
- [ ] 单核优先，SRC 可选
- [ ] Trace Control：**enable + mode** 两个 CSR
- [ ] 在 `PLAN.md` 或本文件中记录上述选择，作为 Phase 2（Trace 接口定义）的输入

---

## 五、与 Phase 2 的衔接

Phase 2 将把上述决策固化为：

1. **Trace Ingress 接口**（Adapter 输入）：`valid`、`pc`、`npc`、`instr`、`commit_pkt` 中用到的位、`trans_info.priv_mode` 等。
2. **Encoder 输出接口**：8-bit 流 + valid；可选 side-channel 表示“消息边界”便于测试。
3. **BlackParrot 接线点**：在 `bp_be` 或 testbench 层从 `calculator.commit_pkt_o` / `trans_info_o` / `decode_info_o` 连线到 Trace 模块（与 `bp_be_nonsynth_cosim` 同源）。

完成 Phase 1 决策后，可直接进入 Phase 2 的接口定义与 RTL 骨架。
