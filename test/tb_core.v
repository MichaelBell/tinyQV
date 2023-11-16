/* A RISC-V core designed to use minimal area.
  
   Aim is to support RV32E 
 */

module tb_core (
    input clk,
    input rstn,

    input [31:0] instr,
    input [31:0] pc,
    input [31:0] data_in,

    output [31:0] data_out,
    output ready,
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

    wire [3:0] alu_op;  // See tiny45_alu for format
    wire [2:0] mem_op;

    wire [3:0] rs1;
    wire [3:0] rs2;
    wire [3:0] rd;

    tiny45_decoder decoder(instr, 
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

        alu_op,  // See tiny45_alu for format
        mem_op,

        rs1,
        rs2,
        rd
             );

    reg [4:0] counter;
    wire [4:0] next_counter = counter + 4;

    reg [3:0] imm_slice;
    reg [3:0] pc_slice;
    always @(posedge clk)
        if (!rstn) begin
            counter <= 0;
        end else begin
            counter <= next_counter;
        end

    tiny45_core core(clk,
        rstn,
        
        imm[counter+:4],

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

        alu_op,
        mem_op,

        rs1,
        rs2,
        rd,

        counter[4:2],
        pc[counter+:4],
        data_in[counter+:4],

        data_out,
        ready,
        branch
        );

endmodule