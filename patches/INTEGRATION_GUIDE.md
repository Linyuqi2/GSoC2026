# Integration Guide: Applying Trace Changes to ZynqParrot

This document describes the modifications made to [zynq-parrot](https://github.com/black-parrot-hdk/zynq-parrot) to integrate the RISC-V instruction tracer.

## Prerequisites

Clone `zynq-parrot` and `riscv-trace` as sibling directories:

```
parent/
├── zynq-parrot/    (clone of black-parrot-hdk/zynq-parrot)
└── riscv-trace/    (this repo's riscv-trace/ folder)
```

## Modified Files

All paths are relative to the `zynq-parrot/` root.

### 1. `cosim/black-parrot-minimal-example/Makefile.design`

Add the DPI sink C++ source to `CSOURCES`:

```makefile
CSOURCES += $(DESIGN_DIR)/bp_riscv_trace_sink.cpp
```

### 2. `cosim/black-parrot-minimal-example/Makefile.hardware`

Add the `RISCV_TRACE_DIR` variable and tracer RTL to `VSOURCES`:

```makefile
# riscv-trace RTL (assumes riscv-trace/ is a sibling of zynq-parrot/)
RISCV_TRACE_DIR ?= $(TOP)/../riscv-trace

VSOURCES  += $(RISCV_TRACE_DIR)/v/bp_riscv_trace_ingress.sv
VSOURCES  += $(RISCV_TRACE_DIR)/v/bp_riscv_trace_encoder.sv
VSOURCES  += $(RISCV_TRACE_DIR)/v/bp_riscv_trace_top.sv
VSOURCES  += $(RISCV_TRACE_DIR)/v/bp_riscv_trace_dpi_sink.sv
```

These lines should be inserted before the `top_zynq.sv` entry.

### 3. `cosim/black-parrot-minimal-example/v/top_zynq.sv`

Insert the following block after the `blackparrot` instance (after line ~412 in the original file):

```systemverilog
localparam trace_commit_pkt_width_lp =
  `bp_be_commit_pkt_width(vaddr_width_p, paddr_width_p, fetch_ptr_p, issue_ptr_p);

logic [trace_commit_pkt_width_lp-1:0] trace_commit_pkt_li;
assign trace_commit_pkt_li = blackparrot.core_minimal.be.calculator.commit_pkt_o;

logic [7:0] trace_data_lo;
logic trace_v_lo, trace_last_lo, trace_ovf_lo;

bp_riscv_trace_top
 #(.bp_params_p(bp_cfg_gp))
 riscv_trace
  (.clk_i(aclk)
   ,.reset_i(~sys_resetn)
   ,.enable_i(1'b1)
   ,.commit_pkt_i(trace_commit_pkt_li)
   ,.trace_data_o(trace_data_lo)
   ,.trace_v_o(trace_v_lo)
   ,.trace_last_o(trace_last_lo)
   ,.overflow_o(trace_ovf_lo)
   );

bp_riscv_trace_dpi_sink
 riscv_trace_sink
  (.clk_i(aclk)
   ,.reset_i(~sys_resetn)
   ,.trace_v_i(trace_v_lo)
   ,.trace_data_i(trace_data_lo)
   ,.trace_last_i(trace_last_lo)
   ,.overflow_i(trace_ovf_lo)
   );
```

### 4. New file: `cosim/black-parrot-minimal-example/bp_riscv_trace_sink.cpp`

Copy `patches/bp_riscv_trace_sink.cpp` from this repository to the path above. This file implements the DPI-C function `bp_trace_sink_byte()` that writes trace bytes to `bp_riscv_trace.bin`.

## Non-Trace Build Fixes (Optional)

The following changes were also made during development but are unrelated to the tracer:

| File | Change |
|---|---|
| `cosim/include/verilator/bsg_zynq_pl.h` | Guard `statsPrintSummary()` behind `VERILATOR_VERSION_INTEGER >= 5024000` for compatibility with older Verilator. |
| `cosim/mk/Makefile.verilator` | Replace `%/V$(TB_MODULE)` with `obj_dir/V$(TB_MODULE)` to fix build target path. |
