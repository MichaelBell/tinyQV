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
*/
`default_nettype none

module tinyqv_alu (
    input [3:0] op,
    input [31:0] a,
    input [31:0] b,
    output reg [31:0] d,
    output reg cmp_res   // 1 for SLT/SLTU/EQ
);

    wire cy_in = op[1] || op[3];
    wire [32:0] a_for_add = {1'b0, a};
    wire [32:0] b_for_add = {1'b0, (op[1] || op[3]) ? ~b : b};
    wire [32:0] sum = a_for_add + b_for_add + {32'b0, cy_in};

    always @(*) begin
        case (op[2:0])
            3'b000: d = sum[31:0];
            3'b111: d = a & b;
            3'b110: d = a | b;
            3'b100: d = a ^ b;
            default: d = 32'b0;
        endcase
    end

    always @(*) begin
        if (op[0])      cmp_res = ~sum[32];
        else if (op[1]) cmp_res = a[31] ^ b_for_add[31] ^ sum[32];
        else            cmp_res = (a == b);
    end

endmodule

module tinyqv_shifter (
    input [3:2] op,
    input [31:0] a,
    input [4:0] b,
    output [31:0] d
);

    wire top_bit = op[3] ? a[31] : 1'b0;
    wire shift_right = op[2];

    wire [31:0] a_for_shift_right = shift_right ? a :
      { a[ 0], a[ 1], a[ 2], a[ 3], a[ 4], a[ 5], a[ 6], a[ 7],
        a[ 8], a[ 9], a[10], a[11], a[12], a[13], a[14], a[15],
        a[16], a[17], a[18], a[19], a[20], a[21], a[22], a[23],
        a[24], a[25], a[26], a[27], a[28], a[29], a[30], a[31]
      };

    wire [32:0] a_for_shift = {top_bit, a_for_shift_right};
    wire [32:0] dr = $signed(a_for_shift) >>> b; 

    assign d = shift_right ? dr[31:0] : 
      { dr[ 0], dr[ 1], dr[ 2], dr[ 3], dr[ 4], dr[ 5], dr[ 6], dr[ 7], 
        dr[ 8], dr[ 9], dr[10], dr[11], dr[12], dr[13], dr[14], dr[15], 
        dr[16], dr[17], dr[18], dr[19], dr[20], dr[21], dr[22], dr[23], 
        dr[24], dr[25], dr[26], dr[27], dr[28], dr[29], dr[30], dr[31]
      };

endmodule
