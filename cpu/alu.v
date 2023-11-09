/* ALU for tiny45.

    RISC-V ALU instructions:
      0000 ADD:  D = A + B
      1000 SUB:  D = A - B
      0010 SLT:  D = (A < B) ? 1 : 0, comparison is signed
      0011 SLTU: D = (A < B) ? 1 : 0, comparison is unsigned
      0111 AND:  D = A & B
      0110 OR:   D = A | B
      0100 XOR:  D = A ^ B
*/

module tiny45_alu (
    input [3:0] op,
    input [3:0] a,
    input [3:0] b,
    input cy_in,
    output [3:0] d,
    output cy_out,   // On final cycle, 1 for SLTU
    output lts       // On final cycle, 1 for SLT
);

    wire [4:0] a_for_add = {1'b0, a};
    wire [4:0] b_for_add = {1'b0, (op[1] || op[3]) ? ~b : b};
    wire [4:0] sum = a_for_add + b_for_add + cy_in;

    function [3:0] operate(
        input [2:0] op_op,
        input [3:0] op_a,
        input [3:0] op_b,
        input [3:0] op_s
    );
        case (op_op)
            3'b000: operate = op_s;
            3'b010, 3'b011: operate = 1'b0;
            3'b111: operate = op_a & op_b;
            3'b110: operate = op_a | op_b;
            3'b100: operate = op_a ^ op_b;
            default: operate = 1'b0;
        endcase
    endfunction

    assign cy_out = sum[4];
    assign d = operate(op[2:0], a, b, sum[3:0]);
    assign lts = a[3] ^ b_for_add[3] ^ sum[4];

endmodule