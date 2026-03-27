# Phase 4：Cosim 抓 Trace 与解析

## 做了什么

1. **RTL 接线**（`zynq-parrot/cosim/black-parrot-minimal-example/v/top_zynq.sv`）  
   - 从 `blackparrot.core_minimal.be.calculator.commit_pkt_o` 引出 `commit_pkt`，送入 `bp_riscv_trace_top`（`bp_params_p` 与 `bp_cfg_gp` 一致）。  
   - `enable_i` 固定为 `1`（后续可改为 CSR，对应 Phase 5/7）。

2. **字节流落盘**  
   - 新增 `riscv-trace/v/bp_riscv_trace_dpi_sink.sv`：在 `trace_v_o` 有效时通过 DPI 调用 C++。  
   - 新增 `zynq-parrot/cosim/black-parrot-minimal-example/bp_riscv_trace_sink.cpp`：将字节写入文件（默认 `bp_riscv_trace.bin`）。  
   - 环境变量 **`BP_RISCV_TRACE_FILE`** 可覆盖输出路径。

3. **构建系统**  
   - `Makefile.hardware`：`RISCV_TRACE_DIR ?= $(TOP)/../riscv-trace`，并加入 `riscv-trace/v/` 下相关 `.sv`。  
   - `Makefile.design`：`CSOURCES += bp_riscv_trace_sink.cpp`。  
   - 要求：**`riscv-trace` 与 `zynq-parrot` 在同一父目录**（与本 GSoC 仓库布局一致）。

4. **解析器**  
   - `riscv-trace/scripts/parse_bp_riscv_trace.py`：按 `docs/PHASE3_RTL_DESIGN.md` 的 MSEO/MDO 布局解析消息（默认 `vaddr` 位宽 39）。

## 如何跑仿真并生成 trace

在 **已能成功 `make build` 的 ZynqParrot 环境**中（注意：trace 只接在 **black-parrot-minimal-example**，不是 `simple-example`）。

从仓库根目录 `gsoc2026`：

```bash
cd zynq-parrot/cosim/black-parrot-minimal-example/verilator
make build
rm -f bp_riscv_trace.bin
BP_RISCV_TRACE_FILE=$PWD/bp_riscv_trace.bin make run
```

若当前在 **`cosim/simple-example/verilator`**，相对路径应写成（不要再套一层 `zynq-parrot/`）：

```bash
cd ../../black-parrot-minimal-example/verilator
```

解析：

```bash
python3 ../../../../riscv-trace/scripts/parse_bp_riscv_trace.py bp_riscv_trace.bin
# 或 JSON 行：
python3 ../../../../riscv-trace/scripts/parse_bp_riscv_trace.py bp_riscv_trace.bin --jsonl
# 无垃圾帧、无尾字节（适合验证）：
python3 ../../../../riscv-trace/scripts/parse_bp_riscv_trace.py bp_riscv_trace.bin --strict
```

## 初步验证脚本（Phase 4）

`riscv-trace/scripts/verify_phase4_trace.py` 做一键检查：

- 文件存在；默认**不允许空文件**（可用 `--allow-empty`）。
- **严格解析**整文件（`iter_messages_strict`）：帧头 / MSEO 错误即失败。
- `--min-messages N`：至少 N 条 discontinuity 消息（退出码 **2** 表示条数不足）。
- `--golden PATH`：与参考 bin **逐字节一致**（可先对稳定用例录一份 golden）。

```bash
# 在生成 bp_riscv_trace.bin 的目录下（路径按你的仓库调整）
python3 /path/to/gsoc2026/riscv-trace/scripts/verify_phase4_trace.py bp_riscv_trace.bin --min-messages 200

# 与仓库内 golden 逐字节一致（bootstrap 占位 hello_world + 当前 RTL 下约 300+ 条消息）
python3 /path/to/gsoc2026/riscv-trace/scripts/verify_phase4_trace.py bp_riscv_trace.bin \
  --golden /path/to/gsoc2026/riscv-trace/golden/black-parrot-minimal-hello_world.trace.bin

# 或
/path/to/gsoc2026/riscv-trace/scripts/verify_phase4_trace.sh bp_riscv_trace.bin --min-messages 200
```

退出码：**0** 通过；**1** 文件/解析/golden 错误；**2** 消息数不足。

### 更新 golden

在跑通 `make run` 且对 trace 满意后：

```bash
/path/to/gsoc2026/riscv-trace/scripts/record_phase4_golden.sh bp_riscv_trace.bin
```

更换 `hello_world.riscv` 或改动 encoder/ingress 后，golden 需重新录制。

## 行为说明

- **Encoder FIFO**：`bp_riscv_trace_encoder` 在 emit 期间将新的 discontinuity **排队**（默认深度 64），并继续在 emit 期间累加顺序提交的 I-CNT；典型 minimal hello_world 下 trace 可达 **数百条消息**（不再是单条就 overflow 丢光）。详见 [PHASE3_RTL_DESIGN.md](PHASE3_RTL_DESIGN.md) §3。
- **overflow**：仅当 **FIFO 满** 仍收到 `disc_li` 时拉高 `overflow_o`。DPI sink **默认不** `$warning`；调试可加 **`+define+BP_RISCV_TRACE_OVERFLOW_DEBUG`**。
- **与 Spike/Dromajo 比对**：当前脚本只解码 RTL 简化帧；与 ISA 参考模型的逐项比对留作后续。

## 依赖

- **`import/black-parrot-subsystems`**：在 `zynq-parrot` 根目录执行  
  `git submodule update --init import/black-parrot-subsystems`。
- **`zynq-parrot/riscv/`**（`bootrom.none.riscv`、`hello_world.riscv`）：完整流程见上游 `make prep`；本仓库提供快捷脚本（无需 sudo，用 `apt-get download` 解压交叉编译器并编译 bootrom，再用 `bp_tethered/demo.riscv` 作为 `hello_world.riscv` 占位）：

```bash
cd /path/to/gsoc2026
./scripts/bootstrap_zynq_parrot_minimal_riscv.sh
```

- **`top_zynq.sv` 中 commit 包宽**：不可在模块体内使用 `` `declare_bp_be_if_widths``（该宏带前导 `,`，仅适用于 `#(` 参数列表）；应使用 `` `bp_be_commit_pkt_width(...)`` 定义 `localparam`（见当前 `black-parrot-minimal-example/v/top_zynq.sv`）。
- **极端负载**：若仍见 `overflow_o`（FIFO 满），可增大 encoder 的 `trace_event_fifo_depth_p` 或在波形中核对事件率；调试告警宏同上。
