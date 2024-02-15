/* Counter register for TinyQV */

module tinyqv_counter #(parameter OUTPUT_WIDTH=4) (
    input clk,
    input rstn,

    input add,
    input [2:0] counter,

    output [OUTPUT_WIDTH-1:0] data
);

    reg [31:0] register;
    reg cy;

    always @(posedge clk) begin
        if (!rstn) begin
            register[3:0] <= 4'h0;
            cy <= 0;
        end else begin
            {cy, register[3:0]} <= {1'b0, register[7:4]} + {4'b0000, (counter == 0) ? add : cy};
        end
        register[31:4] <= {register[3:0], register[31:8]};
    end

    assign data = register[3 + OUTPUT_WIDTH:4];

endmodule
