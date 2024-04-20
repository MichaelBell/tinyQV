/* Register file for SuperTinyQV.

    Targetting RV32E, with hardcoded x0, gp and tp so 13 registers.
 */
`default_nettype none

module tinyqv_registers #(parameter NUM_REGS=16, parameter REG_ADDR_BITS=4) (
    input clk,
    input rstn,

    input wr_en,  // Whether to write to rd.  
                  // rd and data_rd must be the same value as on the previous clock
                  // when this goes high.

    input [REG_ADDR_BITS-1:0] rs1,
    input [REG_ADDR_BITS-1:0] rs2,
    input [REG_ADDR_BITS-1:0] rd,

    output [31:0] data_rs1,
    output [31:0] data_rs2,
    input [31:0] data_rd
);

  reg  wr_en_ok;
  always @(negedge clk) begin
    wr_en_ok <= !wr_en;
  end

  reg [31:0] registers [1:NUM_REGS-1];

  // wr_en is high only for the first half of the clock cycle, 
  // and when rd is the same as on last cycle, so sel_byte is stable.
  wire wr_en_for_latch = wr_en && wr_en_ok;

  genvar i;
  generate
  for (i = 1; i < NUM_REGS; i = i+1) begin
    if (i != 3 && i != 4) begin
        wire sel_byte = (rd == i);
        wire wr_en_this_reg;
    `ifdef SIM    
        assign wr_en_this_reg = wr_en_for_latch && sel_byte;
    `else
        // Use an explicit and gate to minimize possibility of a glitch
        (* keep *) sky130_fd_sc_hd__and2_1 lm_gate ( .A(wr_en_for_latch), .B(sel_byte), .X(wr_en_this_reg) );
    `endif
        always @(wr_en_this_reg /* or data_rd */)
            if (wr_en_this_reg)
                registers[i] <= data_rd;
    end
  end
  endgenerate

  wire [31:0] reg_access [0:2**REG_ADDR_BITS-1];

  generate
        for (i = 0; i < 2**REG_ADDR_BITS; i = i + 1) begin
            if (i == 0 || i >= NUM_REGS) begin
                assign reg_access[i] = 32'h00000000;
            end else if (i == 3) begin // gp is hardcoded to 0x01000400
                assign reg_access[i] = 32'h01000400;
            end else if (i == 4) begin // tp is hardcoded to 0x08000000
                assign reg_access[i] = 32'h08000000;
            end else begin
                assign reg_access[i] = /* wr_en ? data_rd : */ registers[i];
            end
        end
  endgenerate

    assign data_rs1 = reg_access[rs1];
    assign data_rs2 = reg_access[rs2];

endmodule
