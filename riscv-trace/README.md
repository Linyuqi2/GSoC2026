# RISC-V Trace (ZynqParrot / BlackParrot subset)

RTL subtree for the GSoC RISC-V instruction tracer. Loosely coupled with upstream `black-parrot/` — no BP source modifications; integration is done via top-level wiring.

## Directory

- `v/` — SystemVerilog
  - `bp_riscv_trace_ingress.sv` — commit_pkt to N-Trace ingress (combinational)
  - `bp_riscv_trace_encoder.sv` — N-Trace BTM byte stream encoder with event FIFO
  - `bp_riscv_trace_top.sv` — Ingress + Encoder pipeline wrapper
  - `bp_riscv_trace_dpi_sink.sv` — Cosim DPI bridge (one DPI call per trace byte)
- `scripts/` — Trace parser, verification, golden-reference tools
- `golden/` — Reference trace binaries
- `flist.vcs` — VCS file list (paths relative to this directory)

## Dependencies

- BlackParrot headers: `bp_common_defines.svh`, `bp_be_defines.svh` (and BSG-related includes)
- Include paths (adjust to your local BP root):

```
+incdir+$BLACK_PARROT/bp_common/src/include
+incdir+$BLACK_PARROT/bp_be/src/include
+incdir+$BLACK_PARROT/external/basejump_stl/bsg_misc
```
