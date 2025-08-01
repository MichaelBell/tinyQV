/*
 * Copyright (c) 2024 Michael Bell
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// mtime and mtimecmp implementation for TinyQV (optional module)
//
// To save area, only 32-bit time and timecmp are implemented.
// To handle wrap, interrupt will trigger if 0 <= time - timecmp < 2^30.
module tinyQV_time (
    input         clk,
    input         rstn,

    input         time_pulse,     // High for one clock once per microsecond.

    input         set_mtime,
    input         set_mtimecmp,
    input [3:0]   data_in,
    input [2:0]   counter,

    input         read_mtimecmp,  // data_out set to mtime if this is low.
    output [3:0]  data_out,

    output reg    timer_interrupt
);

    wire [3:0] mtime_out;
    reg [31:0] mtimecmp;
    reg time_pulse_r;

    /* verilator lint_off PINMISSING */  // No carry
    tinyqv_counter i_mtime (
        .clk(clk),
        .rstn(rstn),
        .add(time_pulse | time_pulse_r),
        .counter(counter),
        .set(set_mtime),
        .data_in(data_in),
        .data(mtime_out)
    );
    /* verilator lint_on PINMISSING */

    wire [31:4] reg_buf;
    `ifdef SIM
    /* verilator lint_off ASSIGNDLY */
    buf #1 i_regbuf[31:4] (reg_buf, {mtimecmp[3:0], mtimecmp[31:8]});
    /* verilator lint_on ASSIGNDLY */
    `elsif ICE40
    assign reg_buf = {mtimecmp[3:0], mtimecmp[31:8]};
    `elsif SCL_sky130_fd_sc_hd
    /* verilator lint_off PINMISSING */
    sky130_fd_sc_hd__dlygate4sd3_1 i_regbuf[31:4] ( .X(reg_buf), .A({mtimecmp[3:0], mtimecmp[31:8]}) );
    /* verilator lint_on PINMISSING */
    `else
    // On SG13G2 no buffer is required, use direct assignment
    assign reg_buf = {mtimecmp[3:0], mtimecmp[31:8]};
    `endif
    always @(posedge clk) mtimecmp[31:4] <= reg_buf;

    always @(posedge clk) begin
        if (!rstn)
            mtimecmp[3:0] <= 0;
        else begin
            if (set_mtimecmp) mtimecmp[3:0] <= data_in;
            else mtimecmp[3:0] <= mtimecmp[7:4];
        end
    end

    reg cy;
    wire [4:0] comparison = {1'b0, mtime_out} + {1'b0, ~mtimecmp[7:4]} + {4'b0, cy};

    always @(posedge clk) begin
        cy <= (counter == 3'd7) ? 1'b1 : comparison[4];
    end

    always @(posedge clk) begin
        if (counter == 3'd7) timer_interrupt <= (comparison[3:2] == 2'b0);
    end

    always @(posedge clk) begin
        if (counter == 0) time_pulse_r <= 0;
        else time_pulse_r <= time_pulse | time_pulse_r;
    end

    assign data_out = read_mtimecmp ? mtimecmp[7:4] : mtime_out;

    wire _unused = &{comparison[1:0], 1'b0};

endmodule
