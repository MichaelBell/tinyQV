/* A RISC-V core designed to use minimal area.
  
   Aim is to support RV32E 
 */

module tb_alu (
    input clk,
    input rstn,

    input [3:0] op,
    input [31:0] a,
    input [31:0] b,
    output reg [31:0] d,
    output reg cmp
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
    wire cmp_in = (counter == 0) ? 1'b1 : cmp;
    wire cy_out, cmp_out;
    tinyqv_alu alu(op, a[counter+:4], b[counter+:4], cy_in, cmp_in, op_res, cy_out, cmp_out);

    always @(posedge clk) begin
        d[counter+:4] <= op_res;
        cy <= cy_out;
        cmp <= cmp_out;

        if (counter == 5'b11100)
            if (op[2:1] == 2'b01)
                d[0] <= cmp_out;
    end

endmodule