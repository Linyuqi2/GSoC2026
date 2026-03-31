
`include "bp_common_defines.svh"
`include "bp_be_defines.svh"

module bp_riscv_trace_ingress
 import bp_common_pkg::*;
 import bp_be_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
   `declare_bp_proc_params(bp_params_p)
   `declare_bp_core_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p)
   `declare_bp_be_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p, fetch_ptr_p, issue_ptr_p)
   , localparam icnt_incr_width_lp = fetch_ptr_p + 1
   )
  (input [commit_pkt_width_lp-1:0]       commit_pkt_i

   , output logic                         valid_o
   , output logic [vaddr_width_p-1:0]     pc_o
   , output logic [vaddr_width_p-1:0]     npc_o
   , output logic [2:0]                   itype_o
   , output logic [icnt_incr_width_lp-1:0] i_cnt_o
   );

  `declare_bp_be_if(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p, fetch_ptr_p, issue_ptr_p);

  bp_be_commit_pkt_s commit;
  assign commit = commit_pkt_i;

  rv64_instr_rtype_s insn_rtype;
  assign insn_rtype = commit.instr.t.rtype;

  wire [6:0]                         opcode_li = insn_rtype.opcode;
  wire [rv64_funct3_width_gp-1:0]    funct3_li = insn_rtype.funct3;

  wire [vaddr_width_p-1:0] count_ext =
    {{(vaddr_width_p-fetch_ptr_p){1'b0}}, commit.count};

// Sequential next-PC: pc + count*2 (16-bit instruction slots)
  wire [vaddr_width_p-1:0] seq_next_pc = commit.pc + (count_ext << 1);

  wire is_branch_li = (opcode_li == `RV64_BRANCH_OP);
  wire is_jalr_li   = (opcode_li == `RV64_JALR_OP) && (funct3_li == 3'b000);
  wire is_jal_li    = (opcode_li == `RV64_JAL_OP);

  wire taken_li = (commit.npc != seq_next_pc);

  always_comb
    begin
      valid_o  = commit.instret | commit.exception | commit._interrupt;
      pc_o     = commit.pc;
      npc_o    = commit.npc;
      // Retired instruction count in 16-bit slot units
      i_cnt_o  = (commit.count << 1);

      itype_o  = 3'd0;

      if (valid_o)
        begin
          if (commit.exception)
            itype_o = 3'd1;
          else if (commit._interrupt)
            itype_o = 3'd2;
          else if (commit.eret)
            itype_o = 3'd3;
          else if (is_branch_li && !taken_li)
            itype_o = 3'd4;
          else if (is_branch_li && taken_li)
            itype_o = 3'd5;
          else if ((is_jalr_li || is_jal_li) && taken_li)
            // Jump (JAL/JALR): unconditional control flow change
            itype_o = 3'd6;
          else
            itype_o = 3'd0;
        end
    end

endmodule
