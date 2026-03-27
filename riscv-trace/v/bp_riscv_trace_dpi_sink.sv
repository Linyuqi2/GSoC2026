/**
 * bp_riscv_trace_dpi_sink — Co-Sim：每个 trace 字节调用一次 DPI，由 C++ 写文件
 *
 * reset_i：与 bp_riscv_trace_encoder 一致，**高有效**（与 Zynq top 中 ~sys_resetn 相同）。
 */
module bp_riscv_trace_dpi_sink
  (input wire clk_i
   , input wire reset_i
   , input wire trace_v_i
   , input wire [7:0] trace_data_i
   , input wire trace_last_i
   , input wire overflow_i
   );

  import "DPI-C" function void bp_trace_sink_byte
    (input byte unsigned data, input byte unsigned is_last);

  always_ff @(posedge clk_i)
    begin
      if (reset_i)
        begin
          // 复位期间不采样
        end
      else if (overflow_i === 1'b1)
        begin
          // 默认不打印：长 cosim 下 overflow 极多，会刷屏并冲掉前面日志。
          // 需要逐拍告警时，在 Verilator 加：+define+BP_RISCV_TRACE_OVERFLOW_DEBUG
`ifdef BP_RISCV_TRACE_OVERFLOW_DEBUG
          $warning("bp_riscv_trace: encoder overflow (trace event during emit)");
`endif
        end
      else if (trace_v_i)
        begin
          bp_trace_sink_byte(trace_data_i, {7'h0, trace_last_i});
        end
    end

endmodule
