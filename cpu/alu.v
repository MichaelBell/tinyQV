/* ALU for TinyQV.

    RISC-V ALU instructions:
      0000 ADD:  D = A + B
      1000 SUB:  D = A - B
      0010 SLT:  D = (A < B) ? 1 : 0, comparison is signed
      0011 SLTU: D = (A < B) ? 1 : 0, comparison is unsigned
      0111 AND:  D = A & B
      0110 OR:   D = A | B
      0100 XOR/EQ:  D = A ^ B

    Shift instructions (handled by the shifter below):
      0001 SLL: D = A << B
      0101 SRL: D = A >> B
      1101 SRA: D = A >> B (signed)

    Multiply
      1010 MUL: D = B[15:0] * A

    Conditional zero (not implemented here)
      1110 CZERO.eqz
      1111 CZERO.nez
*/

module tinyqv_alu (
    input [3:0] op,
    input [3:0] a,
    input [3:0] b,
    input cy_in,
    input cmp_in,
    output reg [3:0] d,
    output cy_out,
    output reg cmp_res   // On final cycle, 1 for SLT/SLTU/EQ
);

    wire [4:0] a_for_add = {1'b0, a};
    wire [4:0] b_for_add = {1'b0, (op[1] || op[3]) ? ~b : b};
    wire [4:0] sum = a_for_add + b_for_add + {4'b0, cy_in};
    wire [3:0] a_xor_b = a ^ b;

    always @(*) begin
        case (op[2:0])
            3'b000: d = sum[3:0];
            3'b111: d = a & b;
            3'b110: d = a | b;
            3'b100: d = a_xor_b;
            default: d = 4'b0;
        endcase
    end

    always @(*) begin
        if (op[0])      cmp_res = ~sum[4];
        else if (op[1]) cmp_res = a[3] ^ b_for_add[3] ^ sum[4];
        else            cmp_res = cmp_in && a_xor_b == 0;
    end

    assign cy_out = sum[4];

endmodule

module tinyqv_shifter (
    input [3:2] op,
    input [2:0] counter,
    input [31:0] a,
    input [4:0] b,
    output [3:0] d
);

    wire top_bit = op[3] ? a[31] : 1'b0;
    wire shift_right = op[2];

    wire [31:0] a_for_shift_right = shift_right ? a :
      { a[ 0], a[ 1], a[ 2], a[ 3], a[ 4], a[ 5], a[ 6], a[ 7],
        a[ 8], a[ 9], a[10], a[11], a[12], a[13], a[14], a[15],
        a[16], a[17], a[18], a[19], a[20], a[21], a[22], a[23],
        a[24], a[25], a[26], a[27], a[28], a[29], a[30], a[31]
      };

    wire [2:0] c = shift_right ? counter : ~counter;
    wire [5:0] shift_amt = {1'b0, b} + {1'b0, c, 2'b0};
    wire [5:0] adjusted_shift_amt = {1'b0, shift_amt[4:0]};

    wire [34:0] a_for_shift = {{3{top_bit}}, a_for_shift_right};

    reg [3:0] dr;
    always @(*) begin
        if (shift_amt[5]) dr = {4{top_bit}};
        else dr = a_for_shift[adjusted_shift_amt+:4];
    end

    assign d = shift_right ? dr : { dr[ 0], dr[ 1], dr[ 2], dr[ 3]};

endmodule

module tinyqv_mul #(parameter B_BITS=16) (
    input clk,

    input [3:0] a,
    input [B_BITS-1:0] b,

    output [3:0] d
);

    reg [B_BITS-1:0] accum;
    wire [B_BITS+3:0] next_accum = {4'b0, accum} + {{B_BITS{1'b0}}, a} * {4'd0, b};

    always @(posedge clk) begin
        accum <= (a != 4'b0000) ? next_accum[B_BITS+3:4] : {4'b0000, accum[B_BITS-1:4]};
    end

    assign d = next_accum[3:0];

endmodule
