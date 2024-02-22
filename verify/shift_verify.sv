// Formal verification for ALU

module shift_verify (
    input clk,
    input [3:0] op,
    input [31:0] a,
    input [4:0] b,
    output reg [31:0] d,
    output reg valid
);

    localparam OP_SLL = 4'b0001;
    localparam OP_SRL = 4'b0101;
    localparam OP_SRA = 4'b1101;

    reg [4:0] counter = 0;
    always @(posedge clk) begin
        counter <= counter + 4;
    end

    always @(posedge clk) begin
        d[counter +:4] <= d_out;
        if (counter == 5'b11100) begin
            valid <= 1;
        end else begin
            valid <= 0;
        end
    end

    wire [3:0] d_out;
    tinyqv_shifter i_shift(
        op[3:2],
        counter[4:2],
        a,
        b,
        d_out
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
            if ($past(op == OP_SLL)) assert (d == $past(a << b));
            if ($past(op == OP_SRL)) assert (d == $past(a >> b));
            if ($past(op == OP_SRA)) assert (d == $past($signed(a) >>> b));
        end
    end

endmodule
