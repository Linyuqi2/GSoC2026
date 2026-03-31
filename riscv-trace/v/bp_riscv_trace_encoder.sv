
`include "bp_common_defines.svh"
`include "bp_be_defines.svh"

module bp_riscv_trace_encoder
 import bp_common_pkg::*;
 import bp_be_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
   `declare_bp_proc_params(bp_params_p)
   `declare_bp_core_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p)
   `declare_bp_be_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p, fetch_ptr_p, issue_ptr_p)
   , localparam icnt_incr_width_lp = fetch_ptr_p + 1
   , localparam icnt_acc_width_lp  = 16
   , localparam npc_bytes_lp       = (vaddr_width_p + 5) / 6
   , localparam msg_bytes_lp       = 3 + npc_bytes_lp
   , localparam trace_event_fifo_depth_p = 64
   )
  (input                                           clk_i
   , input                                         reset_i
   , input                                         enable_i

   , input                                         valid_i
   , input [vaddr_width_p-1:0]                     pc_i
   , input [vaddr_width_p-1:0]                     npc_i
   , input [2:0]                                   itype_i
   , input [icnt_incr_width_lp-1:0]                i_cnt_i

   , output logic [7:0]                            trace_data_o
   , output logic                                  trace_v_o
   , output logic                                  trace_last_o
   , output logic                                  overflow_o
   );

  function automatic logic discont_3b(input [2:0] t);
    return (t == 3'd1) || (t == 3'd2) || (t == 3'd3)
        || (t == 3'd5) || (t == 3'd6);
  endfunction

  typedef enum logic [1:0] {
    e_idle   = 2'd0
    , e_emit = 2'd1
  } state_e;

  typedef struct packed {
    logic [2:0]               itype;
    logic [vaddr_width_p-1:0] npc;
    logic [icnt_acc_width_lp-1:0] icnt_msg;
  } trace_evt_s;

  localparam fifo_ptr_w_lp = $clog2(trace_event_fifo_depth_p);

  state_e state_r;
  logic [$clog2(msg_bytes_lp)-1:0] idx_r;
  logic [icnt_acc_width_lp-1:0] icnt_acc_r;
  logic overflow_r;

  trace_evt_s fifo_mem [0:trace_event_fifo_depth_p-1];
  logic [fifo_ptr_w_lp-1:0] fifo_wr_r, fifo_rd_r;
  logic [$clog2(trace_event_fifo_depth_p+1)-1:0] fifo_cnt_r;

  logic [vaddr_width_p-1:0] npc_cap_r;
  logic [2:0]               itype_cap_r;
  logic [icnt_acc_width_lp-1:0] icnt_msg_r;

  logic [icnt_acc_width_lp-1:0] icnt_ext_li;
  logic [icnt_acc_width_lp-1:0] icnt_total_li;
  logic [icnt_acc_width_lp-1:0] icnt_sat_li;

  assign icnt_ext_li   = {{(icnt_acc_width_lp-icnt_incr_width_lp){1'b0}}, i_cnt_i};
  assign icnt_total_li = icnt_acc_r + icnt_ext_li;
  assign icnt_sat_li   = (icnt_total_li < icnt_acc_r) ? {icnt_acc_width_lp{1'b1}} : icnt_total_li;

  wire disc_li = valid_i && discont_3b(itype_i);
  wire acc_li  = valid_i && !discont_3b(itype_i);

  wire emit_done = (state_r == e_emit) && (idx_r == msg_bytes_lp - 1'b1);
  wire fifo_empty = (fifo_cnt_r == 0);

// Speculatively compute FIFO count after a potential pop at emit_done
  wire [$clog2(trace_event_fifo_depth_p+1)-1:0] fifo_cnt_after_emit_pop =
    (emit_done && (fifo_cnt_r > 0)) ? (fifo_cnt_r - 1'b1) : fifo_cnt_r;

  wire fifo_will_overflow =
       (state_r == e_emit) && disc_li && (fifo_cnt_after_emit_pop >= trace_event_fifo_depth_p);

  wire can_push_disc = (state_r == e_emit) && disc_li && !fifo_will_overflow;

  wire fifo_do_pop =
       ((state_r == e_idle) && !fifo_empty)
    || ((state_r == e_emit) && emit_done && (fifo_cnt_r > 0));

  assign overflow_o = overflow_r;

  // Circular FIFO pointer increment
  function automatic logic [fifo_ptr_w_lp-1:0] fifo_inc(input logic [fifo_ptr_w_lp-1:0] p);
    return (p == trace_event_fifo_depth_p - 1) ? '0 : (p + 1'b1);
  endfunction

  // Pack 6-bit MDO payload and 2-bit MSEO into one byte
  function automatic logic [7:0] mseo_byte(input [5:0] mdo, input [1:0] mseo);
    return {mdo, mseo};
  endfunction

  function automatic logic [5:0] npc_mdo_chunk(input [vaddr_width_p-1:0] npc, input int unsigned k);
    int unsigned lo = k * 6;
    logic [vaddr_width_p-1:0] sh;
    sh = npc >> lo;
    if (lo >= vaddr_width_p)
      return 6'd0;
    else
      return 6'(sh & 6'h3f);
  endfunction

  logic [7:0] trace_data_li;
  logic trace_v_li, trace_last_li;

  always_comb
    begin
      logic [$clog2(msg_bytes_lp)-1:0] npc_idx;
      trace_v_li    = 1'b0;
      trace_last_li = 1'b0;
      trace_data_li = 8'h00;
// Emit one byte per cycle: header, itype, icnt, then npc chunks
      if (state_r == e_emit)
        begin
          trace_v_li = 1'b1;
          if (idx_r == 0)
            trace_data_li = mseo_byte(6'h04, 2'b00);
          else if (idx_r == 1)
            trace_data_li = mseo_byte({3'd0, itype_cap_r}, 2'b00);
          else if (idx_r == 2)
            trace_data_li = mseo_byte(icnt_msg_r[5:0], 2'b00);
          else if (idx_r >= 3)
            begin
              npc_idx = idx_r - 2'd3;
              if (npc_idx < npc_bytes_lp)
                begin
                  if (idx_r == msg_bytes_lp - 1)
                    begin
                      trace_data_li = mseo_byte(npc_mdo_chunk(npc_cap_r, int'(npc_idx)), 2'b11);
                      trace_last_li = 1'b1;
                    end
                  else
                    trace_data_li = mseo_byte(npc_mdo_chunk(npc_cap_r, int'(npc_idx)), 2'b00);
                end
            end
        end
    end

  assign trace_data_o = trace_data_li;
  assign trace_v_o    = trace_v_li;
  assign trace_last_o = trace_last_li;
  // Main sequential logic: FIFO management and FSM transitions
  always_ff @(posedge clk_i)
    begin
      if (reset_i)
        begin
          state_r     <= e_idle;
          idx_r       <= '0;
          icnt_acc_r  <= '0;
          overflow_r  <= 1'b0;
          npc_cap_r   <= '0;
          itype_cap_r <= '0;
          icnt_msg_r  <= '0;
          fifo_wr_r   <= '0;
          fifo_rd_r   <= '0;
          fifo_cnt_r  <= '0;
        end
      else if (!enable_i)
        begin
          state_r    <= e_idle;
          fifo_wr_r  <= '0;
          fifo_rd_r  <= '0;
          fifo_cnt_r <= '0;
        end
      else
        begin
          overflow_r <= overflow_r | fifo_will_overflow;

          if (can_push_disc)
            begin
              fifo_mem[fifo_wr_r].itype    <= itype_i;
              fifo_mem[fifo_wr_r].npc      <= npc_i;
              fifo_mem[fifo_wr_r].icnt_msg <= icnt_sat_li;
              fifo_wr_r                    <= fifo_inc(fifo_wr_r);
            end

          if (fifo_do_pop)
            fifo_rd_r <= fifo_inc(fifo_rd_r);

          fifo_cnt_r <= fifo_cnt_r
                      - (fifo_do_pop ? 1'b1 : 1'b0)
                      + (can_push_disc ? 1'b1 : 1'b0);

          unique case (state_r)
            e_idle:
              begin
                if (!fifo_empty)
                  begin
                    trace_evt_s ev;
                    ev          = fifo_mem[fifo_rd_r];
                    icnt_msg_r  <= ev.icnt_msg;
                    npc_cap_r   <= ev.npc;
                    itype_cap_r <= ev.itype;
                    idx_r       <= '0;
                    state_r     <= e_emit;
                  end
                else if (disc_li)
                  begin
                    icnt_msg_r  <= icnt_sat_li;
                    icnt_acc_r  <= '0;
                    npc_cap_r   <= npc_i;
                    itype_cap_r <= itype_i;
                    idx_r       <= '0;
                    state_r     <= e_emit;
                  end
                else if (acc_li)
                  icnt_acc_r <= icnt_sat_li;
              end

            e_emit:
              begin
                if (acc_li)
                  icnt_acc_r <= icnt_sat_li;

                if (can_push_disc)
                  icnt_acc_r <= '0;

                if (!emit_done)
                  idx_r <= idx_r + 1'b1;
                else if (fifo_cnt_r > 0)
                  begin
                    trace_evt_s ev;
                    ev          = fifo_mem[fifo_rd_r];
                    icnt_msg_r  <= ev.icnt_msg;
                    npc_cap_r   <= ev.npc;
                    itype_cap_r <= ev.itype;
                    idx_r       <= '0;
                  end
                else
                  begin
                    state_r <= e_idle;
                    idx_r   <= '0;
                  end
              end

            default: state_r <= e_idle;
          endcase
        end
    end

endmodule
