/* TinyQV: A RISC-V core designed to use minimal area.
  
   This core module takes decoded instructions and produces output data
 */
`default_nettype none

module tinyqv_core #(parameter NUM_REGS=16, parameter REG_ADDR_BITS=4) (
    input clk,
    input rstn,

    input [31:0] imm,

    input is_load,
    input is_alu_imm,
    input is_auipc,
    input is_store,
    input is_alu_reg,
    input is_lui,
    input is_branch,
    input is_jalr,
    input is_jal,
    input is_system,
    input is_stall,

    input [3:0] alu_op,  // See tinyqv_alu for format
    input [2:0] mem_op,

    input [REG_ADDR_BITS-1:0] rs1,
    input [REG_ADDR_BITS-1:0] rs2,
    input [REG_ADDR_BITS-1:0] rd,

    input [23:0] pc,
    input [23:0] next_pc,
    input [31:0] data_in,
    input load_data_ready,

    output reg [31:0] data_out,  // Data for the active store instruction
    output [27:0] addr_out,
    output address_ready,   // The addr_out holds the address for the active load/store instruction
    output reg instr_complete,  // The current instruction will complete this clock, so the instruction may be updated.
                            // If no new instruction is available all a NOOP should be issued, which will complete in 1 cycle.
    output branch           // addr_out holds the address to branch to
);

    // Forward declarations
    reg [1:0] cycle;

    wire is_shift = alu_op[1:0] == 2'b01;

    ///////// Register file /////////

    wire [31:0] data_rs1;
    wire [31:0] data_rs2;
    reg [31:0] data_rd;
    reg wr_en;

    tinyqv_registers #(.REG_ADDR_BITS(REG_ADDR_BITS), .NUM_REGS(NUM_REGS)) 
        i_registers(clk, rstn, wr_en, rs1, rs2, rd, data_rs1, data_rs2, data_rd);


    ///////// ALU /////////

    wire is_slt = alu_op[3:1] == 3'b001;

    wire [3:0] alu_op_in = alu_op;
    wire [31:0] alu_a_in = (is_auipc || is_jal) ? {8'h0, pc} : data_rs1;
    wire [31:0] alu_b_in = (is_alu_reg || is_branch) ? data_rs2 : imm;
    wire [31:0] alu_out;
    wire cmp_out;

    tinyqv_alu i_alu(alu_op_in, alu_a_in, alu_b_in, alu_out, cmp_out);

    ///////// Shifter /////////

    wire [4:0] shift_amt = is_alu_imm ? imm[4:0] : data_rs2[4:0];
    wire [31:0] shift_out;
    tinyqv_shifter i_shift(alu_op[3:2], data_rs1, shift_amt, shift_out);


    ///////// Writeback /////////

    always @(*) begin
        wr_en = 0;
        data_rd = 0;
        if (is_alu_imm || is_alu_reg || is_auipc) begin
            wr_en = 1;
            if (is_slt)
                data_rd = {31'b0, cmp_out};
            else if (is_shift)
                data_rd = shift_out;
            else
                data_rd = alu_out;

        end else if (is_load && load_data_ready) begin
            wr_en = 1;
            data_rd = data_in;

            if (mem_op[1:0] == 2'b00) data_rd[31:8] = {{24{mem_op[2] ? 1'b0 : data_in[7]}}};
            else if (mem_op[1:0] == 2'b01) data_rd[31:16] = {{16{mem_op[2] ? 1'b0 : data_in[15]}}};

        end else if (is_lui) begin
            wr_en = 1;
            data_rd = imm;
        end else if (is_jal || is_jalr) begin
            wr_en = 1;
            data_rd = {8'h0, next_pc};
        end

        if (cycle == 0) wr_en = 0;
    end


    ///////// Branching /////////

    wire take_branch = cmp_out ^ mem_op[0];
    assign branch = ((is_jal || is_jalr) && cycle == 1) || (is_branch && take_branch);


    ///////// Load / Store /////////

    assign addr_out = alu_out[27:0];

    assign data_out[ 7: 0] = data_rs2[ 7: 0];
    assign data_out[15: 8] = data_rs2[15: 8] & {{8{mem_op[1] | mem_op[0]}}};
    assign data_out[31:16] = data_rs2[31:16] & {{16{mem_op[1]}}};
    

    ///////// Cycle management /////////

    always @(posedge clk) begin
        if (!rstn) cycle <= 0;
        else begin
            if (instr_complete) cycle <= 0;
            else if (cycle != 2'b11) cycle <= cycle + 1;
        end
    end

    reg load_done;
    always @(*) begin
        instr_complete = 0;
        if (is_store || is_branch || is_stall || is_system)
            instr_complete = 1;
        else if (cycle[0] && (is_auipc || is_lui || is_jal || is_jalr || is_alu_imm || is_alu_reg))
            instr_complete = 1;
        else if (load_done && is_load)
            instr_complete = 1;
    end

    always @(posedge clk) begin
        load_done <= load_data_ready && cycle != 2'b00;
    end

    assign address_ready = is_load || is_store;

endmodule
