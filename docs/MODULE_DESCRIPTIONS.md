# Module Descriptions — ZynqParrot Cosim (black-parrot-minimal-example)

This document describes the key modules in the ZynqParrot cosimulation infrastructure,
split into two sections: the **original modules** (before trace) and the
**newly added RISC-V trace modules** (after trace).

For each module we list:
- **I/O** — summarized input/output interfaces (not every individual wire)
- **Function** — what the module does
- **Role** — why this module is needed in the system

---

## Part 1: Original Modules (Before Trace)

### 1.1 Testbench Level (`bsg_nonsynth_zynq_testbench.sv`)

File: `zynq-parrot/cosim/v/bsg_nonsynth_zynq_testbench.sv`

#### 1.1.1 `bsg_nonsynth_dpi_to_axil` (instance: `axil0`) + DPI Control (`cosim_main`, `bsg_dpi_next`, `bsg_dpi_time`)

| | Description |
|---|---|
| **I/O** | `axil0` — Input: `aclk`, `aresetn`, AXI-Lite slave-side ready/response signals. Output: AXI-Lite master-side address/data/control signals (`gp0_axi_*`). DPI tasks — `cosim_main` (C++ → RTL entry point), `bsg_dpi_next` (advance one clock edge), `bsg_dpi_time` (query simulation time). |
| **Function** | `axil0` bridges DPI function calls from C++ into AXI-Lite bus transactions: when C++ calls `shell_read()`/`shell_write()`, this module converts the call into proper AXI-Lite protocol signals on the `gp0_axi_*` bus. `cosim_main` launches the C++ entry point from an `initial` block; `bsg_dpi_next` lets C++ advance the simulation by one clock cycle; `bsg_dpi_time` returns the current simulation timestamp. |
| **Role** | Together they form the **PS emulation layer**: `axil0` emulates the Zynq PS GP0 AXI master port, while the DPI tasks provide the cosimulation control loop — C++ drives the simulation forward tick by tick and issues AXI transactions in between. In real hardware the ARM core would perform these functions natively. |

#### 1.1.2 `bsg_nonsynth_axi_mem` (instance: `axi_mem`)

| | Description |
|---|---|
| **I/O** | Input: `clk_i`, `reset_i`, full AXI slave interface (`hp0_axi_*`). Output: AXI read data and response signals |
| **Function** | A behavioral AXI memory model. Accepts AXI read/write transactions and stores data in a large internal array (`mem_els_p = 2^28` entries). |
| **Role** | Emulates the Zynq PS DDR memory accessed through the HP0 port. When BlackParrot issues DRAM load/store requests, after address translation they reach this module, which models the actual memory. Enabled by the `AXI_MEM_ENABLE` macro. |

#### 1.1.3 `top` (instance: `dut`)

File: `zynq-parrot/cosim/black-parrot-minimal-example/v/top.v`

| | Description |
|---|---|
| **I/O** | Input: `aclk`, `aresetn`, GP0 AXI-Lite slave signals, HP0 AXI master response signals. Output: GP0 AXI-Lite response signals, HP0 AXI master request signals |
| **Function** | A thin Verilog wrapper that passes all parameters and ports directly through to `top_zynq`. Contains no logic of its own. |
| **Role** | Decouples the generic testbench from the design-specific `top_zynq` implementation. Every ZynqParrot design provides its own `top.v` with the same port interface, enabling the testbench to remain unchanged across designs. |

---

### 1.2 PL Core (`top_zynq.sv`)

File: `zynq-parrot/cosim/black-parrot-minimal-example/v/top_zynq.sv`

#### 1.2.1 `bsg_zynq_pl_shell` (instance: `zps`) + CSR Registers + `bsg_bootrom`

| | Description |
|---|---|
| **I/O** | **Shell** — Input: GP0 AXI-Lite slave interface (`gp0_axi_*`), PL→PS FIFO data/valid, PS→PL FIFO ready. Output: CSR data registers, PS→PL FIFO data/valid, PL→PS FIFO ready. **CSR logic** — distributes CSR values to `sys_resetn`, `dram_base`, `freeze`, interrupt signals, `bootrom_addr`; collects `minstret`, credits, bootrom data back for PS reads. **Bootrom** — Input: `addr_i` from CSR. Output: 32-bit bootrom word. |
| **Function** | `zps` decodes GP0 AXI-Lite transactions into CSR read/write and FIFO enqueue/dequeue operations, providing 10 PS→PL registers, 4 PL→PS registers, and 2 bidirectional FIFO channels. The CSR combinational logic fans out control signals (reset, freeze, DRAM base, interrupts) and collects status (minstret, credits). The bootrom is a read-only memory initialized from a `.rom` file, whose contents PS reads word-by-word through CSR transactions for NBF program loading. |
| **Role** | The **control plane** of the PL. All PS commands — configuration, status polling, program loading, and bootrom access — pass through this shell and its associated CSR/bootrom logic. It abstracts the AXI protocol into simple register and FIFO interfaces for the rest of the design. |

#### 1.2.2 `bp_endpoint_to_fifos` (instance: `f2b`)

| | Description |
|---|---|
| **I/O** | **FIFO side** — 2× PS→PL FIFO (data/valid/ready) input, 2× PL→PS FIFO (data/valid/ready) output. **Bedrock side** — `proc[2]`: mem_fwd output + mem_rev input. `dev[1]`: mem_fwd input + mem_rev output. Also outputs `credits_used_o`. |
| **Function** | Serializes/deserializes Bedrock stream packets into 32-bit FIFO words. On the processor side, it converts PS FIFO writes into Bedrock `mem_fwd` requests and Bedrock `mem_rev` responses back into FIFO reads. On the device side, it accepts Bedrock `mem_fwd` requests from the crossbar and returns `mem_rev` responses through the other FIFO pair. |
| **Role** | The bridge between the PS/FIFO world and the Bedrock on-chip network. It allows PS to inject memory requests (for NBF program loading) and to receive I/O forwarded requests from BlackParrot (for host I/O like putchar). |

#### 1.2.3 `bp_me_xbar_stream` (instances: `fwd_xbar` + `rev_xbar`)

| | Description |
|---|---|
| **I/O** | **fwd_xbar** — Input: 3 Bedrock mem_fwd streams (proc[0]=I$, proc[1]=D$, proc[2]=endpoint) + destination select. Output: 2 Bedrock mem_fwd streams (dev[0]=mem, dev[1]=endpoint). **rev_xbar** — Input: 2 Bedrock mem_rev streams (dev[0]=mem, dev[1]=endpoint) + destination select. Output: 3 Bedrock mem_rev streams back to processors. |
| **Function** | `fwd_xbar` routes forward (request) messages from sources to sinks based on address: host device addresses → dev[1] (endpoint), all other addresses → dev[0] (memory). `rev_xbar` routes reverse (response) messages back to the correct source based on the `lce_id` field in the response payload. |
| **Role** | The Bedrock interconnect fabric. Multiplexes requests from multiple masters (I-cache, D-cache, PS endpoint) to the correct device, and demultiplexes responses back. |

#### 1.2.4 `bp_unicore_lite` (instance: `blackparrot`)

| | Description |
|---|---|
| **I/O** | Input: `clk_i`, `reset_i`, `cfg_bus_i` (freeze, NPC, cache modes, etc.), `mem_rev_*` (responses from rev_xbar), interrupt signals. Output: `mem_fwd_*` (requests to fwd_xbar, 2 ports: I-cache and D-cache) |
| **Function** | A minimal single-core RISC-V processor (RV64GC) with I-cache and D-cache. Fetches instructions, executes them, and issues Bedrock memory requests for cache misses and uncached accesses. |
| **Role** | The DUT (Device Under Test) — the actual RISC-V processor being prototyped. Everything else in the system exists to support running software on this core. |

#### 1.2.5 `bp_axil_master` (instance: `mem2axil`) + Address Translation

| | Description |
|---|---|
| **I/O** | **Bedrock side** — `mem_fwd_*` input (from fwd_xbar dev[0]), `mem_rev_*` output (to rev_xbar dev[0]). **AXI side** — `hp0_axi_*` output to testbench (and ultimately to `axi_mem`), `hp0_axi_*` input (read data and responses). |
| **Function** | `mem2axil` converts Bedrock stream protocol memory requests into AXI-Lite transactions and converts AXI-Lite responses back into Bedrock reverse messages. The address translation logic then remaps BlackParrot's DRAM addresses (base `0x8000_0000`) to physical PS DRAM addresses by computing `(addr ^ 0x8000_0000) + dram_base`, and promotes AXI-Lite single-beat signals to full AXI4 protocol (adding burst, length, size fields). |
| **Role** | The **data plane exit** from PL to external memory. Bridges the Bedrock protocol to AXI and translates BlackParrot's fixed DRAM address space to wherever PS has actually allocated memory. |

---

### 1.3 C++ Side

#### 1.3.1 `main.cpp` + `ps.cpp`

Files: `zynq-parrot/cosim/src/main.cpp`, `zynq-parrot/cosim/black-parrot-minimal-example/ps.cpp`

| | Description |
|---|---|
| **I/O** | Called via DPI from testbench's `cosim_main`. Uses `bsg_zynq_pl` API (`shell_read`, `shell_write`, `allocate_dram`, `tick`) to communicate with PL through DPI → `axil0` → `zps`. |
| **Function** | `main.cpp` is the C++ entry point: it parses arguments, creates the platform abstraction object (`bsg_zynq_pl`), and calls `ps_main()`. `ps.cpp` implements the PS application: (1) verifies CSR connectivity, (2) allocates DRAM and sets base address, (3) freezes processor and loads program via NBF through FIFOs, (4) unfreezes processor, (5) polls for host I/O requests from BlackParrot and handles them (putchar, finish), (6) reports minstret and wall-clock time. |
| **Role** | The "software driver" that controls the entire system. In real Zynq hardware this would be a Linux application running on the ARM PS; in cosim it runs as C++ linked into the Verilator binary. The same `ps.cpp` code runs in both environments, providing software portability. |

---

## Part 2: Newly Added Modules (After Trace)

All RTL modules below are instantiated inside `top_zynq.sv`. They form a
unidirectional pipeline: processor retire information → standardization →
N-Trace encoding → DPI transport → file output.

### 2.1 Hierarchical Probe (`assign` statement)

File: `top_zynq.sv`, lines 420–421

| | Description |
|---|---|
| **I/O** | Input: `blackparrot.core_minimal.be.calculator.commit_pkt_o` (hierarchical path into BlackParrot internals). Output: `trace_commit_pkt_li` (local wire in `top_zynq`) |
| **Function** | Uses a SystemVerilog hierarchical reference to read the commit packet signal from deep inside the BlackParrot processor pipeline, without modifying any BlackParrot source code or ports. |
| **Role** | Provides the raw retirement information needed for instruction trace. The hierarchical probe approach avoids any invasive changes to the processor RTL, though it only works in simulation (not synthesizable for ASIC). |

### 2.2 `bp_riscv_trace_ingress` (sub-module inside `bp_riscv_trace_top`)

File: `riscv-trace/v/bp_riscv_trace_ingress.sv`

| | Description |
|---|---|
| **I/O** | Input: `commit_pkt_i` (BlackParrot-specific commit packet structure). Output: `valid_o`, `pc_o`, `npc_o`, `itype_o` (3-bit instruction type), `i_cnt_o` (retired 16-bit instruction slot count) |
| **Function** | Pure combinational logic that parses the BlackParrot-specific `commit_pkt` structure into a standardized set of trace signals. Decodes the opcode to classify instructions into 7 types (none, exception, interrupt, eret, branch-not-taken, branch-taken, jump). Computes sequential next-PC using `pc + (count << 1)` for compressed instruction support. Priority: exception > interrupt > eret > branch > jump > sequential. |
| **Role** | The **processor-specific adapter layer**. This is the only module that needs to change when porting the tracer to a different RISC-V processor. It translates proprietary commit packet formats into a generic interface that the encoder understands. |

### 2.3 `bp_riscv_trace_encoder` (sub-module inside `bp_riscv_trace_top`)

File: `riscv-trace/v/bp_riscv_trace_encoder.sv`

| | Description |
|---|---|
| **I/O** | Input: `clk_i`, `reset_i`, `enable_i`, `valid_i`, `pc_i`, `npc_i`, `itype_i`, `i_cnt_i` (from ingress). Output: `trace_data_o` (8-bit byte), `trace_v_o` (byte valid), `trace_last_o` (end-of-message marker), `overflow_o` (FIFO overflow flag, latched) |
| **Function** | A sequential state machine (idle/emit) that generates N-Trace BTM (Branch Trace Message) byte streams. Accumulates an I-CNT counter during sequential execution; on a discontinuity event (branch taken, jump, exception, etc.), emits a multi-byte message containing: message type (0x04), itype, accumulated I-CNT, and target NPC. Uses MSEO (2-bit) + MDO (6-bit) encoding per byte. Includes a 64-entry event FIFO to buffer discontinuity events that arrive during an ongoing emit sequence. |
| **Role** | The core trace encoding engine. Converts a stream of per-cycle retirement events into a compact, standards-aligned byte stream that can be decoded offline. The FIFO ensures no events are lost even when the emit pipeline is busy (up to FIFO capacity). |

### 2.4 `bp_riscv_trace_top` (instance: `riscv_trace`)

File: `riscv-trace/v/bp_riscv_trace_top.sv`

| | Description |
|---|---|
| **I/O** | Input: `clk_i`, `reset_i`, `enable_i`, `commit_pkt_i`. Output: `trace_data_o`, `trace_v_o`, `trace_last_o`, `overflow_o` |
| **Function** | Instantiates `bp_riscv_trace_ingress` and `bp_riscv_trace_encoder` in series, connecting the ingress outputs to the encoder inputs internally. Exposes a single, clean top-level interface. |
| **Role** | A convenience wrapper that allows `top_zynq` to instantiate the entire ingress+encoder pipeline with a single module instance. Simplifies the integration point and keeps `top_zynq` clean. |

### 2.5 `bp_riscv_trace_dpi_sink` (instance: `riscv_trace_sink`)

File: `riscv-trace/v/bp_riscv_trace_dpi_sink.sv`

| | Description |
|---|---|
| **I/O** | Input: `clk_i`, `reset_i`, `trace_v_i`, `trace_data_i` (8-bit), `trace_last_i`, `overflow_i`. Output: none (side effect: DPI call to C++) |
| **Function** | On every clock posedge where `trace_v_i` is asserted, calls the DPI-C function `bp_trace_sink_byte(data, is_last)` to pass one byte to the C++ side. Silent during reset. Optionally warns on overflow when `BP_RISCV_TRACE_OVERFLOW_DEBUG` is defined. |
| **Role** | The RTL-to-C++ boundary for trace data. It is the counterpart of `bsg_nonsynth_dpi_to_axil` but in the opposite direction: instead of C++ driving RTL, here RTL pushes data to C++. This is a simulation-only module (DPI does not exist in synthesized hardware). |

### 2.6 `bp_riscv_trace_sink.cpp`

File: `zynq-parrot/cosim/black-parrot-minimal-example/bp_riscv_trace_sink.cpp`

| | Description |
|---|---|
| **I/O** | Receives DPI calls: `bp_trace_sink_byte(data, is_last)`. Writes to output file. |
| **Function** | Implements the C-linkage DPI function `bp_trace_sink_byte()`. On first call, opens the output file (path from `BP_RISCV_TRACE_FILE` environment variable, default `bp_riscv_trace.bin`). Each call appends one byte to the file. When `is_last` is set (end of a trace message), flushes the file buffer. |
| **Role** | The final stage of the trace pipeline. Persists the N-Trace encoded byte stream to disk for offline analysis, decoding, or comparison against a reference trace. |

---

## Part 3: Planned Modules (Future Work)

The following modules are not yet implemented but are planned for the GSoC project.
They extend the existing trace pipeline with FPGA deployment support and runtime control.

### 3.1 `bp_riscv_trace_axi_stream_sink` (planned, inside `top_zynq.sv`)

| | Description |
|---|---|
| **I/O** | Input: trace byte stream from `bp_riscv_trace_top` (same signals as `dpi_sink`). Output: AXI-Stream interface (`tdata`, `tvalid`, `tready`, `tlast`) routed out through `top_zynq` → `top.v` → testbench / Vivado block diagram. |
| **Function** | Packs 8-bit trace bytes into 32-bit AXI-Stream beats, asserting `tlast` on message boundaries. Provides the physical output path for FPGA deployment, replacing the simulation-only DPI sink. Selected via compile-time `ifdef` alongside the existing `dpi_sink`. |
| **Role** | The FPGA counterpart of `bp_riscv_trace_dpi_sink`. While DPI cannot exist in synthesized hardware, AXI-Stream is a standard on-chip transport that can be connected to Vivado FIFO IPs, DMA engines, or external interfaces. |

### 3.2 AXI-Stream FIFO IP (planned, Vivado Block Diagram)

| | Description |
|---|---|
| **I/O** | Input: AXI-Stream from `bp_riscv_trace_axi_stream_sink` (via `top.v` ports). Output: AXI-Lite or AXI memory-mapped interface accessible by the PS through GP0. |
| **Function** | A Xilinx FIFO IP instantiated in the Vivado block diagram (`axi_trace_bd.tcl`). Buffers the AXI-Stream trace data and exposes it as a memory-mapped register that PS can poll via `shell_read()`. In cosim this module is not needed (trace goes through DPI instead). |
| **Role** | Bridges the streaming trace output to the PS-accessible AXI address space on FPGA. Without this FIFO, the PS would have no way to read the trace byte stream from the PL in hardware. |

### 3.3 `bsg_zynq_trace.h/.cpp` (planned, C++ side)

| | Description |
|---|---|
| **I/O** | Uses `bsg_zynq_pl` API (`shell_read`, `shell_write`) to access trace CSRs and FIFO via the existing GP0 DPI/AXI path. Writes trace data to output file. |
| **Function** | A unified C++ driver class that provides `trace_enable()`, `trace_disable()`, and `trace_dump_to_file()`. In cosim mode, it only manages CSRs (trace data is already written to file by the DPI sink). In FPGA co-emulation mode, it additionally reads the AXI-Stream FIFO via `shell_read()` and writes the bytes to disk. |
| **Role** | Provides a portable trace control API that works identically in both cosim and FPGA environments. Integrates into `ps.cpp` so that trace can be enabled before program start and dumped after program finish, without the user needing to know which output path is active. |

---

## Summary: Data Flow

### Before Trace

```
C++ (ps.cpp)
  │ DPI (shell_read/write)
  ▼
axil0 ──gp0_axi──► zps ──CSR/FIFO──► f2b ──Bedrock──► fwd_xbar ──► dev[0]: mem2axil ──► addr_xlat ──hp0_axi──► axi_mem
                                       │                   ▲               ▲                                        │
                                       │ dev[1]            │ proc[0,1]     │ mem_rev                                │
                                       ◄───────────── rev_xbar ◄───────── blackparrot ◄────────────────────────────┘
```

### After Trace (added path, shown separately)

```
blackparrot (internal commit_pkt_o)
  │ hierarchical probe (assign)
  ▼
bp_riscv_trace_top
  ├── ingress  (commit_pkt → valid/pc/npc/itype/icnt)
  └── encoder  (→ N-Trace byte stream)
        │
        │ trace_data/v/last/overflow
        ▼
bp_riscv_trace_dpi_sink
        │ DPI-C: bp_trace_sink_byte()
        ▼
bp_riscv_trace_sink.cpp
        │ fwrite
        ▼
bp_riscv_trace.bin
```

The trace path is **completely independent** from the original data path.
No existing module interfaces are modified.
