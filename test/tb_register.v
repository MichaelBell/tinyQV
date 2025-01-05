/* A RISC-V core designed to use minimal area.
  
   Aim is to support RV32E 
 */

module tb_register (
    input clk,
    input rstn,

    input wr_en,

    input [3:0] rs1,
    input [3:0] rs2,
    input [3:0] rd,

    output reg [31:0] rs1_out,
    output reg [31:0] rs2_out,
    input [31:0] rd_in
);

`ifdef COCOTB_SIM
initial begin
  $dumpfile ("register.vcd");
  $dumpvars (0, tb_register);
  #1;
end
`endif

    reg [4:0] last_counter;
    wire [4:0] counter = last_counter + 4;
    always @(posedge clk)
        if (!rstn) begin
            last_counter <= 0;
        end else begin
            last_counter <= counter;
        end

    wire [3:0] data_rs1;
    wire [3:0] data_rs2;
    wire [23:1] return_addr;
    tinyqv_registers registers(clk, rstn, wr_en, last_counter[4:2], rs1, rs2, rd, data_rs1, data_rs2, rd_in[last_counter+:4], return_addr);

    always @(posedge clk) begin
        rs1_out[last_counter+:4] <= data_rs1;
        rs2_out[last_counter+:4] <= data_rs2;
    end

endmodule