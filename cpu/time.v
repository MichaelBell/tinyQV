/*
 * Copyright (c) 2024 Michael Bell
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// mtime and mtimecmp implementation for TinyQV (optional module)
//
// To save area, only 32-bit time and timecmp are implemented.
// To handle wrap, interrupt will trigger if 0 <= time - timecmp < 2^30.
//
// TODO: This implementation is much larger than it needs to be.
//       The mtime increment could be done by a much smaller adder over
//       several clocks without breaking anything.
//       Avoiding the large compare would only be very slightly harder.
//       It might be nice if the 4-bit data and cycle count were an alternative
//       interface for peripherals, that might significantly reduce routing congestion.
module tinyQV_time (
    input         clk,
    input         rstn,

    input         time_pulse,     // High for one clock once per microsecond.

    input         set_mtime,
    input         set_mtimecmp,
    input [31:0]  data_in,

    input         read_mtimecmp,  // data_out set to mtime if this is low.
    output [31:0] data_out,

    output reg    timer_interrupt
);

    reg [31:0] mtime;
    wire [31:0] mtimecmp;

    latch_reg32_p l_mtimecmp (
        .clk(clk),
        .wen(!rstn || set_mtimecmp),
        .data_in(data_in),
        .data_out(mtimecmp)
    );

    wire [31:0] comparison = mtime - mtimecmp;
    always @(posedge clk) timer_interrupt <= (comparison[31:30] == 0);
    assign data_out = read_mtimecmp ? mtimecmp : mtime;

    wire [31:0] next_mtime = mtime + 32'd1;

    always @(posedge clk) begin
        if (!rstn) begin
            mtime <= 0;
        end else begin
            if (set_mtime) mtime <= data_in;
            else if (time_pulse) mtime <= next_mtime;
        end
    end

    wire _unused = &{comparison[29:0], 1'b0};

endmodule
