`default_nettype none
`timescale 1ns / 100ps

/* A RISC-V core designed to use minimal area.
  
   Aim is to support RV32E 
 */

module tb_core (
    input clk,
    input rstn,

    input [31:0] instr,
    input [31:0] pc,
    input [31:0] data_in,
    input load_data_ready,
    input is_stall,

    output [31:0] data_out,
    output [31:0] addr_out,
    output address_ready,
    output instr_complete,
    output branch
);

`ifdef COCOTB_SIM
initial begin
  $dumpfile ("core.vcd");
  $dumpvars (0, tb_core);
  #1;
end
`endif

    wire [31:0] imm;

    wire is_load;
    wire is_alu_imm;
    wire is_auipc;
    wire is_store;
    wire is_alu_reg;
    wire is_lui;
    wire is_branch;
    wire is_jalr;
    wire is_jal;
    wire is_system;

    wire [2:0] instr_len;
    wire [3:0] alu_op;  // See tinyqv_alu for format
    wire [2:0] mem_op;

    wire [3:0] rs1;
    wire [3:0] rs2;
    wire [3:0] rd;

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
        is_system,

        instr_len,
        alu_op,  // See tinyqv_alu for format
        mem_op,

        rs1,
        rs2,
        rd
             );

    reg [4:0] counter;
    wire [4:0] next_counter = counter + 4;

    assign addr_out[31:28] = 0;

    wire [31:0] next_pc = pc + {29'd0, instr_len};

    tinyqv_core core(clk,
        rstn,
        
        imm,

        is_load && !is_stall,
        is_alu_imm && !is_stall,
        is_auipc && !is_stall,
        is_store && !is_stall,
        is_alu_reg && !is_stall,
        is_lui && !is_stall,
        is_branch && !is_stall,
        is_jalr && !is_stall,
        is_jal && !is_stall,
        is_system && !is_stall,
        is_stall,

        alu_op,
        mem_op,

        rs1,
        rs2,
        rd,

        pc[23:0],
        next_pc[23:0],
        data_in,
        {{4{load_data_ready}}},

        data_out,
        addr_out[27:0],
        address_ready,
        instr_complete,
        branch
        );

endmodule