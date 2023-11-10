/* Register file for tiny45.

    Targetting RV32E, with hardcoded x0, gp and tp so 13 registers.

    4-bit access and the registers are always rotated by 4 bits every clock.

    The read bit address is one ahead of write bit address, and both increment every clock.
 */

module tiny45_registers #(parameter NUM_REGS=16, parameter REG_ADDR_BITS=4) (
    input clk,
    input rstn,

    input wr_en,  // Whether to write to rd.

    input [2:0] counter,

    input [REG_ADDR_BITS-1:0] rs1,
    input [REG_ADDR_BITS-1:0] rs2,
    input [REG_ADDR_BITS-1:0] rd,

    output [3:0] data_rs1,
    output [3:0] data_rs2,
    input [3:0] data_rd
);

    reg [31:0] registers [1:NUM_REGS-1];
    wire [3:0] reg_access [0:2**REG_ADDR_BITS-1];

    genvar i;
    generate
        for (i = 0; i < 2**REG_ADDR_BITS; i = i + 1) begin
            if (i == 0 || i >= NUM_REGS) begin
                assign reg_access[i] = 0;
            end else if (i == 3) begin // gp is hardcoded to 0x00001000
                assign reg_access[i] = {3'b0, (counter == 3)};
            end else if (i == 4) begin // tp is hardcoded to 0x10000000
                assign reg_access[i] = {3'b0, (counter == 7)};
            end else begin
                always @(posedge clk) begin
                    if (wr_en && rd == i)
                        registers[i][3:0] <= data_rd;
                    else
                        registers[i][3:0] <= registers[i][7:4];
                    
                    registers[i][31:4] <= {registers[i][3:0], registers[i][31:8]};
                end

                assign reg_access[i] = registers[i][7:4];
            end
        end
    endgenerate 

    assign data_rs1 = reg_access[rs1];
    assign data_rs2 = reg_access[rs2];

endmodule
