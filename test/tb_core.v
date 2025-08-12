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

    output [31:0] data_out,
    output [31:0] addr_out,
    output address_ready,
    output instr_complete,
    output branch,
    output [23:1] return_addr,

    input interrupt,
    input [15:0] interrupt_req,
    input timer_interrupt,
    output interrupt_pending
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
    wire is_ret;
    wire is_system;

    wire [2:1] instr_len;
    wire [3:0] alu_op;  // See tinyqv_alu for format
    wire [2:0] mem_op;

    wire [3:0] rs1;
    wire [3:0] rs2;
    wire [3:0] rd;

    wire [2:0] additional_mem_ops;
    wire mem_op_increment_reg;

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

        instr_len,
        alu_op,  // See tinyqv_alu for format
        mem_op,

        rs1,
        rs2,
        rd,

        additional_mem_ops,
        mem_op_increment_reg
             );

    reg [4:0] counter;
    wire [4:0] next_counter = counter + 4;

    wire [3:0] data_out_slice;
    reg [31:0] data_out_reg;
    always @(posedge clk) begin
        if (!rstn) begin
            counter <= 0;
        end else begin
            counter <= next_counter;
        end
        data_out_reg[counter+:4] <= data_out_slice;
    end

    assign data_out[31:28] = data_out_slice;
    assign data_out[27:0] = data_out_reg[27:0];
    assign addr_out[31:28] = 0;

    wire [31:0] next_pc = pc + {29'd0, instr_len, 1'b0};

    wire debug_reg_wen;
    wire [3:0] debug_rd;

    tinyqv_core core(clk,
        rstn,
        
        imm[counter+:4],
        imm[11:0],

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
        1'b0,
        interrupt,

        alu_op,
        mem_op,

        rs1,
        rs2,
        rd,

        counter[4:2],
        pc[counter+:4],
        next_pc[counter+:4],
        data_in[counter+:4],
        load_data_ready,

        data_out_slice,
        addr_out[27:0],
        address_ready,
        instr_complete,
        branch,
        return_addr,

        interrupt_req,
        timer_interrupt,
        interrupt_pending,

        debug_reg_wen,
        debug_rd
        );

endmodule