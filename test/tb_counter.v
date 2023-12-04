/* A RISC-V core designed to use minimal area.
  
   Aim is to support RV32E 
 */

module tb_counter (
    input clk,
    input rstn,

    input add,

    output reg [31:0] val
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
    tiny45_counter i_mcount(clk, rstn, add, last_counter[4:2], data);

    always @(posedge clk) begin
        val[last_counter+:4] <= data;
    end

endmodule