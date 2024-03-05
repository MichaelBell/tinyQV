/* A RISC-V core designed to use minimal area.
  
   Aim is to support RV32E 
 */

module tb_decode (
    input clk,
    input rstn,

    input [31:0] instr,

    output [31:0] imm,

    output is_load,
    output is_alu_imm,
    output is_auipc,
    output is_store,
    output is_alu_reg,
    output is_lui,
    output is_branch,
    output is_jalr,
    output is_jal,
    output is_ret,
    output is_system,

    output [2:0] instr_len,

    output [3:0] alu_op,  // See tinyqv_alu for format
    output [2:0] mem_op,

    output [3:0] rs1,
    output [3:0] rs2,
    output [3:0] rd,

    output [2:0] additional_mem_ops,
    output       mem_op_increment_reg
);

`ifdef COCOTB_SIM
initial begin
  $dumpfile ("decode.vcd");
  $dumpvars (0, tb_decode);
  #1;
end
`endif

    tinyqv_decoder decoder(instr, 
        imm,

        is_load,
        is_alu_imm,
        is_auipc,
        is_store,
        is_alu_reg,
        is_lui,
        is_branch,
        is_jalr,
        is_jal,
        is_ret,
        is_system,

        instr_len[2:1],

        alu_op,  // See tinyqv_alu for format
        mem_op,

        rs1,
        rs2,
        rd,

        additional_mem_ops,
        mem_op_increment_reg
             );

    assign instr_len[0] = 1'b0;

endmodule