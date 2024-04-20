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

    output [31:0] rs1_out,
    output [31:0] rs2_out,
    input [31:0] rd_in
);

`ifdef COCOTB_SIM
initial begin
  $dumpfile ("register.vcd");
  $dumpvars (0, tb_register);
  #1;
end
`endif

    tinyqv_registers registers(clk, rstn, wr_en, rs1, rs2, rd, rs1_out, rs2_out, rd_in);

endmodule