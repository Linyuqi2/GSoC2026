/**
 * bp_riscv_trace_top — Ingress + Encoder 级联（testbench / top_zynq 可直接例化）
 */
`include "bp_common_defines.svh"
`include "bp_be_defines.svh"

module bp_riscv_trace_top
 import bp_common_pkg::*;
 import bp_be_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
   `declare_bp_proc_params(bp_params_p)
   `declare_bp_core_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p)
   `declare_bp_be_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p, fetch_ptr_p, issue_ptr_p)
   , localparam icnt_incr_width_lp = fetch_ptr_p + 1
   )
  (input                               clk_i
   , input                             reset_i
   , input                             enable_i
   , input [commit_pkt_width_lp-1:0]   commit_pkt_i

   , output logic [7:0]                trace_data_o
   , output logic                      trace_v_o
   , output logic                      trace_last_o
   , output logic                      overflow_o
   );

  logic                         valid_lo;
  logic [vaddr_width_p-1:0]     pc_lo, npc_lo;
  logic [2:0]                 itype_lo;
  logic [icnt_incr_width_lp-1:0] i_cnt_lo;

  bp_riscv_trace_ingress
   #(.bp_params_p(bp_params_p))
   ingress
    (.commit_pkt_i(commit_pkt_i)
     ,.valid_o(valid_lo)
     ,.pc_o(pc_lo)
     ,.npc_o(npc_lo)
     ,.itype_o(itype_lo)
     ,.i_cnt_o(i_cnt_lo)
     );

  bp_riscv_trace_encoder
   #(.bp_params_p(bp_params_p))
   encoder
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.enable_i(enable_i)

     ,.valid_i(valid_lo)
     ,.pc_i(pc_lo)
     ,.npc_i(npc_lo)
     ,.itype_i(itype_lo)
     ,.i_cnt_i(i_cnt_lo)

     ,.trace_data_o(trace_data_o)
     ,.trace_v_o(trace_v_o)
     ,.trace_last_o(trace_last_o)
     ,.overflow_o(overflow_o)
     );

endmodule
