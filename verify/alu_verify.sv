// Formal verification for ALU

module alu_verify (
    input clk,
    input [3:0] op,
    input [31:0] a,
    input [31:0] b,
    output reg [31:0] d,
    output reg cy,
    output reg cmp,
    output reg valid
);

    localparam OP_ADD = 4'b0000;
    localparam OP_SUB = 4'b1000;
    localparam OP_SLT = 4'b0010;
    localparam OP_SLTU= 4'b0011;
    localparam OP_AND = 4'b0111;
    localparam OP_OR  = 4'b0110;
    localparam OP_XOR = 4'b0100;

    reg [4:0] counter = 0;
    always @(posedge clk) begin
        counter <= counter + 4;
    end

    always @(posedge clk) begin
        d[counter +:4] <= d_out;
        cy <= cy_out;
        cmp <= cmp_out;
        if (counter == 5'b11100) begin
            valid <= 1;
        end else begin
            valid <= 0;
        end
    end

    wire cy_in = (counter == 0) ? (op[1] || op[3]) : cy;
    wire cmp_in = (counter == 0) ? 1'b1 : cmp;
    wire cy_out;
    wire cmp_out;
    wire [3:0] d_out;
    tinyqv_alu i_alu(
        op,
        a[counter +:4],
        b[counter +:4],
        cy_in,
        cmp_in,
        d_out,
        cy_out,
        cmp_out
    );

    reg f_past_valid = 0;
    always @(posedge clk) begin
        f_past_valid <= 1;

        // inputs only change when count 0
        if (counter != 0) begin
            assume(op == $past(op));
            assume(a == $past(a));
            assume(b == $past(b));
        end

        if (f_past_valid && valid) begin
            if ($past(op == OP_ADD)) assert ({cy, d} == $past({1'b0, a} + {1'b0, b}));
            if ($past(op == OP_SUB)) assert (d == $past(a - b));
            if ($past(op == OP_SLT)) assert (cmp == $past($signed(a) < $signed(b)));
            if ($past(op == OP_SLTU)) assert (cmp == $past(a < b));
            if ($past(op == OP_XOR)) assert (cmp == $past(a == b));
            if ($past(op == OP_AND)) assert (d == $past(a & b));
            if ($past(op == OP_OR)) assert (d == $past(a | b));
            if ($past(op == OP_XOR)) assert (d == $past(a ^ b));
        end
    end

endmodule
