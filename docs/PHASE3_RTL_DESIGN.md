# Phase 3：Trace RTL 设计说明

本文档说明 `riscv-trace/v/` 下模块的职责、与 Phase 2 规格的对应关系，以及**为何**采用当前实现（组合/时序划分、I-CNT、字节格式限制等）。

---

## 1. 文件清单

| 文件 | 说明 |
|------|------|
| `bp_riscv_trace_ingress.sv` | 从 `bp_be_commit_pkt_s` 推导 `valid/pc/npc/itype/i_cnt`（组合） |
| `bp_riscv_trace_encoder.sv` | I-CNT 累计 + 简化 MSEO 帧 + 单消息 FSM |
| `bp_riscv_trace_top.sv` | 上述两者级联 |

---

## 2. Ingress：为何全组合

- **不寄存 commit**：与 `calculator.commit_pkt_o` 同拍可见；Encoder 在 **posedge** 采样 `valid/itype/...`，天然再对齐到时序域。
- **valid**：`instret \| exception \| _interrupt`，与 Phase 2 §3.2、§4.1 一致。
- **顺序下一 PC**：`seq_next = pc + (count << 1)`。BlackParrot 的 `count` 按取指/退休槽计数，左移一位等价于按 **16-bit 指令单元** 前进；比固定 `pc+4` 更贴合压缩指令与多槽退休，从而使 **B-type not-taken（itype=4）** 判定为 `npc == seq_next`。

### itype 与 Phase 2 的对应

| 条件 | itype | 备注 |
|------|-------|------|
| `exception` | 1 | 最高优先级 |
| `_interrupt` | 2 | |
| `eret` | 3 | |
| B-type 且 `!taken` | 4 | `taken = (npc != seq_next)` |
| B-type 且 `taken` | 5 | |
| JALR（funct3=000）或 JAL 且 `taken` | 6 | 规范正文只写 JALR；若不包含 **JAL**，无条件 `jal` 将无 trace 不连续点，软件难以重建流 |

### `i_cnt_o`（每拍增量）

- 取 `commit.count << 1`，表示本拍退休的 **16-bit 半字数**（每道 32-bit 槽对应 2 个半字）。
- 位宽 `fetch_ptr_p+1`，覆盖 `count` 左移一位后的范围。

---

## 3. Encoder：I-CNT 为何放在 Encoder

- Phase 2 规定 Ingress 输出**本拍增量**；N-Trace 语义上 **I-CNT** 表示“自上一同步点以来的指令单元数”，需在 **Encoder** 内累计。
- **遇 discontinuity**（itype ∈ {1,2,3,5,6}）：输出消息中的 I-CNT = **当前累计 + 本拍增量**（饱和到 16-bit 累加器），然后清零累计器。
- **itype 4（not-taken branch）**：不发消息，仅 **累加** I-CNT（BTM 行为）。
- **itype 0**：顺序，仅累加。

### 与完整 N-Trace 的差异（刻意简化）

- 消息体 **不是** 从规范 PDF 逐字段抄写的合法 Nexus 包；采用固定长度 **简化帧**，便于仿真与 C++ 解析器原型。
- **I-CNT 在帧内仅占 6-bit MDO**（取 `icnt_msg[5:0]`），大间隔会 **截断/饱和**；长测需软件侧接受或后续扩展多字节 I-CNT 字段。

### 字节布局（每字节 `{MDO[5:0], MSEO[1:0]}`，与 Phase 2 §5.1 一致）

设 `npc_bytes = ceil(vaddr_width_p / 6)`，**总长度 `msg_bytes = 3 + npc_bytes`**：

| 序号 | 内容 | MSEO |
|------|------|------|
| 0 | `MDO=6'h04`（表示“类 IndirectBranch”简化头，非认证 TCODE 编码） | `00` |
| 1 | `MDO={3'b0, itype[2:0]}` | `00` |
| 2 | `MDO=icnt_msg[5:0]` | `00` |
| 3 … `3+npc_bytes-2` | `npc` 的 6-bit 切片（低索引对应低 VA） | `00` |
| `msg_bytes-1` | `npc` 最后一片 | `11`（`trace_last_o=1`） |

`npc` 切片：`chunk(k) = (npc >> (6*k)) & 6'h3f`，自动处理 `vaddr_width_p` 非 6 整除。

### 单消息 FSM + Phase 4 事件 FIFO

- Phase 2 假定 **无背压**；每条 discontinuity 仍用固定 `msg_bytes` 周期顺序输出（面积小、行为确定）。
- **Phase 4**：`bp_riscv_trace_encoder` 内增加 **discontinuity 事件 FIFO**（参数 `trace_event_fifo_depth_p`，默认 64）。正在 `e_emit` 时若又来需发包的 discontinuity，则 **入队**（并继续用 `acc_li` 累加 I-CNT），而不是立刻 overflow。
- **仍可能 overflow**：FIFO 满时 `disc_li` 无法入队 → `overflow_o` 置位（可接波形；DPI sink 可选 `$warning`，见 Phase 4 文档）。极端事件率下可增大 `trace_event_fifo_depth_p` 或改为 AXI-Stream（后续阶段）。

### `enable_i` 行为

- 拉低时：**回到 IDLE**，**丢弃**未发完的字节；**不累计** I-CNT。与“CSR 关闭 trace”的最简语义一致；若需“排空 FIFO”可后续改为独立逻辑。

---

## 4. 仿真集成提示

- `+incdir+` 需包含 BlackParrot 的 `bp_common` / `bp_be` include 路径（与 `bp_be_nonsynth_cosim.sv` 相同）。
- 将 `riscv-trace/flist.vcs` 中文件加入工程；在 testbench 中例化 `bp_riscv_trace_top`，`commit_pkt_i` 接 `calculator.commit_pkt_o`（层次名依 DUT 而定）。

---

## 5. 自检清单

- [x] Ingress：`valid/pc/npc/itype/i_cnt` 与 Phase 2 §4.1、§4.2 对齐（含 `seq_next`）
- [x] Encoder：`trace_data_o`/`trace_v_o`、MSEO 末字节 `11`
- [x] 文档标明与 **完整 N-Trace** 的二进制差异及 I-CNT 截断限制
