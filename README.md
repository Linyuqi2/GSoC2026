# GSoC 2026 — RISC-V Instruction Trace for ZynqParrot

This repository contains the design, implementation, and documentation for adding RISC-V instruction tracing to the [ZynqParrot](https://github.com/black-parrot-hdk/zynq-parrot) cosimulation and co-emulation infrastructure.

The tracer captures retired instruction information from the [BlackParrot](https://github.com/black-parrot/black-parrot) RISC-V processor and encodes it into an [N-Trace](https://github.com/riscv-non-isa/tg-nexus-trace) byte stream for offline analysis and debugging.

## Repository Structure

```
├── riscv-trace/            RTL modules and verification scripts
│   ├── v/                  SystemVerilog source (ingress, encoder, top, dpi_sink)
│   ├── scripts/            Trace parser, golden-reference recorder, verification
│   └── golden/             Reference trace binaries
├── docs/
│   └── diagrams/           Block diagrams (PNG)
├── patches/                Changes applied to zynq-parrot for integration
│   ├── bp_riscv_trace_sink.cpp   DPI sink C++ implementation
│   └── INTEGRATION_GUIDE.md      Step-by-step modification instructions
├── PLAN.md                 16-week project plan
└── README.md
```

## Architecture Overview

```
BlackParrot (commit_pkt_o)
  │  hierarchical probe
  ▼
bp_riscv_trace_top  ──►  ingress  ──►  encoder  ──►  dpi_sink  ──►  C++ file output
                     (processor-     (N-Trace        (DPI-C
                      specific)       byte stream)    boundary)
```

The trace pipeline is instantiated inside `top_zynq.sv` and is **completely independent** from the original data path — no existing module interfaces are modified.

## Quick Start

See [patches/INTEGRATION_GUIDE.md](patches/INTEGRATION_GUIDE.md) for how to apply the tracer to a local ZynqParrot checkout.

## References

- [RISC-V N-Trace Specification v1.0](https://github.com/riscv-non-isa/tg-nexus-trace)
- [IEEE-ISTO 5001-2012, Nexus 5001 Standard](https://nexus5001.org/)
- [RISC-V Processor Trace Specification](https://github.com/riscv-non-isa/riscv-trace-spec)
