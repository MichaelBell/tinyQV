/* A RISC-V core designed to use minimal area.
  
   Aim is to support RV32E 
 */

module tb_counter (
    input clk,
    input rstn,

    input add,

    output reg [31:0] val,
    output reg cy
);

`ifdef COCOTB_SIM
initial begin
  $dumpfile ("counter.vcd");
  $dumpvars (0, tb_counter);
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

    wire [3:0] data;
    tinyqv_counter i_mcount(clk, rstn, add, last_counter[4:2], 1'b0, 4'b0, data, cy_out);

    always @(posedge clk) begin
        val[last_counter+:4] <= data;
        if (last_counter[4:2] == 3'b111) cy <= cy_out;
    end

endmodule