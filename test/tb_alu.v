/* A RISC-V core designed to use minimal area.
  
   Aim is to support RV32E 
 */

module tb_alu (
    input clk,
    input rstn,

    input [3:0] op,
    input [31:0] a,
    input [31:0] b,
    output reg [31:0] d
);

`ifdef COCOTB_SIM
initial begin
  $dumpfile ("alu.vcd");
  $dumpvars (0, tb_alu);
  #1;
end
`endif

    reg [4:0] counter = 0;
    wire [4:0] next_counter = counter + 4;
    always @(posedge clk)
        if (!rstn)
            counter <= 0;
        else
            counter <= next_counter;

    reg cy;
    wire cy_in = (counter == 0) ? (op[1] || op[3]) : cy;
    wire [3:0] op_res;
    wire cy_out, lts;
    tiny45_alu alu(op, a[counter+:4], b[counter+:4], cy_in, op_res, cy_out, lts);

    always @(posedge clk) begin
        d[counter+:4] <= op_res;
        cy <= cy_out;

        if (counter == 5'b11100)
            if (op[2:0] == 3'b011)
                d[0] <= ~cy_out;
            else if (op[2:0] == 3'b010)
                d[0] <= lts;
    end

endmodule