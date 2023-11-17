/* Tiny45: A RISC-V core designed to use minimal area.
  
   This core module takes decoded instructions and produces output data
 */

module tiny45_core #(parameter NUM_REGS=16, parameter REG_ADDR_BITS=4) (
    input clk,
    input rstn,

    input [3:0] imm,

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

    input [3:0] alu_op,  // See tiny45_alu for format
    input [2:0] mem_op,

    input [REG_ADDR_BITS-1:0] rs1,
    input [REG_ADDR_BITS-1:0] rs2,
    input [REG_ADDR_BITS-1:0] rd,

    input [2:0] counter,    // Sub cycle counter, must increment on every clock
    input [3:0] pc,
    input [3:0] data_in,
    input load_data_ready,

    output [31:0] data_out,
    output address_ready,   // The data_out holds the address for the active load/store instruction
    output instr_complete,  // The current instruction will complete this clock, so the instruction may be updated.
                            // If no new instruction is available all a NOOP should be issued, which will complete in 1 cycle.
    output branch           // data_out holds the address to branch to
);

    wire [3:0] data_rs1;
    wire [3:0] data_rs2;
    reg [3:0] data_rd;
    reg wr_en;

    tiny45_registers #(.REG_ADDR_BITS(REG_ADDR_BITS), .NUM_REGS(NUM_REGS)) 
        i_registers(clk, rstn, wr_en, counter, rs1, rs2, rd, data_rs1, data_rs2, data_rd);

    wire last_count = (counter == 7);

    reg cy;
    reg cmp;
    wire [3:0] alu_a_in = is_auipc ? pc : data_rs1;
    wire [3:0] alu_b_in = is_alu_reg ? data_rs2 : imm;
    wire [3:0] alu_out;
    wire cy_in = (counter == 0) ? (alu_op[1] || alu_op[3]) : cy;
    wire cmp_in = (counter == 0) ? 1'b1 : cmp;
    wire cy_out, cmp_out;

    tiny45_alu i_alu(alu_op, alu_a_in, alu_b_in, cy_in, cmp_in, alu_out, cy_out, cmp_out);

    always @(posedge clk) begin
        cy <= cy_out;
        cmp <= cmp_out;
    end

    always @(*) begin
        wr_en = 0;
        data_rd = alu_out;
        if (is_alu_imm || is_alu_reg || is_auipc) begin
            wr_en = 1;
        end else if (is_load && load_data_ready) begin  // TODO
            wr_en = 1;
            data_rd = data_in;
        end else if (is_lui) begin
            wr_en = 1;
            data_rd = imm;
        end       
    end

    reg [2:0] cycle;
    always @(posedge clk) begin
        if (!rstn) cycle <= 0;
        else if (last_count) begin
            if (instr_complete) cycle <= 0;
            else if (cycle != 3'b111) cycle <= cycle + 1;
        end
    end

    reg load_done;
    always @(posedge clk) begin
        if (counter == 0)
            load_done <= load_data_ready;
    end

    // TODO
    reg [31:0] tmp_data;
    reg [3:0] tmp_data_in;
    
    always @(*) begin
        if (cycle == 0) begin
            tmp_data_in = alu_out;
        end else begin
            tmp_data_in = data_rs2;
        end
    end

    always @(posedge clk) begin
        tmp_data <= {tmp_data_in, tmp_data[31:4]};
    end

    // TODO
    assign data_out = tmp_data;  // TODO
    assign address_ready = last_count && (cycle == 0) && (is_load || is_store);
    assign instr_complete = last_count && (is_alu_imm || is_alu_reg || is_auipc || is_lui ||
                     (cycle == 1 && is_store) || (load_done && is_load));
    assign branch = 0;

endmodule