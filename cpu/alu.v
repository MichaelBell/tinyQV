/* ALU for tiny45.

    RISC-V ALU instructions:
      0000 ADD:  D = A + B
      1000 SUB:  D = A - B
      0010 SLT:  D = (A < B) ? 1 : 0, comparison is signed
      0011 SLTU: D = (A < B) ? 1 : 0, comparison is unsigned
      0111 AND:  D = A & B
      0110 OR:   D = A | B
      0100 XOR/EQ:  D = A ^ B

    Shift instructions (not handled here):
      0001 SLL: D = A << B
      0101 SRL: D = A >> B
      1101 SRA: D = A >> B (signed)
*/

module tiny45_alu (
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
    wire [4:0] sum = a_for_add + b_for_add + cy_in;
    wire [3:0] a_xor_b = a ^ b;

    always @(*) begin
        case (op[2:0])
            3'b000: d = sum[3:0];
            3'b111: d = a & b;
            3'b110: d = a | b;
            3'b100: d = a_xor_b;
            default: d = 1'b0;
        endcase
    end

    always @(*) begin
        if (op[0])      cmp_res = ~sum[4];
        else if (op[1]) cmp_res = a[3] ^ b_for_add[3] ^ sum[4];
        else            cmp_res = cmp_in && a_xor_b == 0;
    end

    assign cy_out = sum[4];

endmodule