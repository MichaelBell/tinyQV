/* Tech specific buffer cell */

`default_nettype none

module tinyqv_buffer (
    input A,
    output X
);

    `ifdef SIM
    /* verilator lint_off ASSIGNDLY */
    buf #1 i_buf (X, A);
    /* verilator lint_on ASSIGNDLY */
    `elsif SYNTH_FPGA
    assign X = A;
    `elsif SCL_sky130_fd_sc_hd
    /* verilator lint_off PINMISSING */
    sky130_fd_sc_hd__dlygate4sd3_1 i_buf ( .X(X), .A(A) );
    /* verilator lint_on PINMISSING */
    `elsif SCL_sg13g2_stdcell
    // On SG13G2 no buffer is required, use direct assignment
    assign X = A;
    `else
    gf180mcu_fd_sc_mcu7t5v0__dlya_1 i_buf ( .Z(X), .I(A) );
    `endif

endmodule
