// DPI companion for bp_riscv_trace_dpi_sink (Verilator cosim)
#include <cstdio>
#include <cstdlib>

extern "C" void bp_trace_sink_byte(unsigned char data, unsigned char is_last)
{
  static FILE *fp = nullptr;
  if (fp == nullptr) {
    const char *path = std::getenv("BP_RISCV_TRACE_FILE");
    if (path == nullptr || path[0] == '\0')
      path = "bp_riscv_trace.bin";
    fp = std::fopen(path, "wb");
    if (fp == nullptr) {
      std::fprintf(stderr, "bp_riscv_trace_sink: could not open %s\n", path);
      std::abort();
    }
  }
  std::fputc(static_cast<int>(data), fp);
  if (is_last & 1)
    std::fflush(fp);
}
