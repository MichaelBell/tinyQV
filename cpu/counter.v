/* Counter register for TinyQV */

module tinyqv_counter #(parameter OUTPUT_WIDTH=4) (
    input clk,
    input rstn,

    input add,
    input [2:0] counter,

    output [OUTPUT_WIDTH-1:0] data,
    output cy_out
);

    reg [31:0] register;
    reg cy;

    wire [4:0] increment_result = {1'b0, register[7:4]} + {4'b0000, (counter == 0) ? add : cy};
    always @(posedge clk) begin
        if (!rstn) begin
            register[3:0] <= 4'h0;
            cy <= 0;
        end else begin
            {cy, register[3:0]} <= increment_result;
        end
        register[31:4] <= {register[3:0], register[31:8]};
    end

    assign data = register[3 + OUTPUT_WIDTH:4];
    assign cy_out = increment_result[4];

endmodule
