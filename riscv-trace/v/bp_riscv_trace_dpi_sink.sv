
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
          //
        end
      else if (overflow_i === 1'b1)
        begin
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
