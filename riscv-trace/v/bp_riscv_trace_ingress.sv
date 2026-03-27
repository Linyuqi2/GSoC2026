/**
 * bp_riscv_trace_ingress — BlackParrot commit → N-Trace 风格 Ingress（组合逻辑）
 *
 * 设计要点（为何这样写）：
 * - **纯组合**：不寄存 commit，避免与 calculator 再差一拍；Encoder 在下一拍对 valid/itype 采样即可。
 * - **valid**：与 Phase 2 一致，instret | exception | _interrupt 表示本拍提交语义有效。
 * - **顺序下一 PC**：用 pc + (count<<1)，与 BP 按 16-bit 指令槽对齐的退休语义一致；不用固定 +4，
 *   以便压缩指令 / 多槽提交时 branch not-taken 判定正确。
 * - **itype 优先级**：先异常/中断/eret，再解析 opcode，避免异常指令被误判成分支。
 */
`include "bp_common_defines.svh"
`include "bp_be_defines.svh"

module bp_riscv_trace_ingress
 import bp_common_pkg::*;
 import bp_be_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
   `declare_bp_proc_params(bp_params_p)
   `declare_bp_core_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p)
   `declare_bp_be_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p, fetch_ptr_p, issue_ptr_p)
   // 每拍退休的 16-bit 单元数上界：count 最大 (2^fetch_ptr_p-1)，×2 后为半字个数
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

  // 顺序流上下一 PC（16-bit 对齐步进）
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
      // I-CNT 增量：每个 32-bit 退休槽 = 2 个 16-bit 半字 × count
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
            // Phase 2 只点名 JALR；JAL 若不归类会导致无条件跳转无包。此处与 JALR 同属“非条件分支类 discontinuity”。
            itype_o = 3'd6;
          else
            itype_o = 3'd0;
        end
    end

endmodule
