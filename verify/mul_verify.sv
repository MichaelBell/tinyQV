// Formal verification for Multiplier

`ifndef B_BITS
`define B_BITS 5
`endif

module mul_verify #(parameter B_BITS=`B_BITS) (
    input clk,
    input [31:0] a,
    input [B_BITS-1:0] b,
    output reg [31:0] d,
    output reg valid
);

    reg [5:0] counter = 0;
    always @(posedge clk) begin
        counter <= counter + 4;
    end

    always @(posedge clk) begin
        d[counter[4:0] +:4] <= d_out;
        if (counter == 6'b111100) begin
            valid <= 1;
        end else begin
            valid <= 0;
        end
    end

    wire [3:0] d_out;
    tinyqv_mul #(.B_BITS(B_BITS)) i_mul(
        clk,
        a[counter[4:0] +:4] & {4{counter[5]}},
        b,
        d_out
    );

    reg f_past_valid = 0;
    always @(posedge clk) begin
        f_past_valid <= 1;

        // inputs only change when count 0
        if (counter != 0) begin
            assume(a == $past(a));
            assume(b == $past(b));
        end

        if (f_past_valid && valid) begin
            assert (d == $past(a * b));
        end
    end

endmodule
