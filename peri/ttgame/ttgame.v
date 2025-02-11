/* Copyright 2025 (c) Michael Bell
   SPDX-License-Identifier: Apache-2.0

   A very simple 8-bit PWM peripheral
   */

`default_nettype none

// Reference design https://github.com/TinyTapeout/vga-playground/blob/main/src/examples/common/gamepad_pmod.v
// But this uses the game_clk as a clock (hopefully I can get that to work in SDC and CTS).
// This reduces the amount of synchronization that is required.

module tt_game (
    input clk,
    /* verilator lint_off SYNCASYNCNET */
    input rstn,
    /* verilator lint_on SYNCASYNCNET */

    // Controller inputs
    input game_latch,
    (* keep *) input game_clk,
    input game_data,

    // Data outputs
    output [11:0] controller_1,
    output [11:0] controller_2
);

    reg [23:0] data_reg;
    reg [23:0] shift_reg;
    reg [1:0] game_latch_sync;
    reg data_latch_wen;

    // Clock in the data using the game clock.
    // Note async reset because the will (probably) be no game clocks during reset.
    always @(posedge game_clk or negedge rstn) begin
        if (!rstn) shift_reg <= 24'hffffff;
        else shift_reg <= {shift_reg[22:0], game_data};
    end

    always @(posedge clk) begin
        if (!rstn) game_latch_sync <= 0;
        else game_latch_sync <= {game_latch_sync[0], game_latch};
    end

    // Use negedge clock to drive the data latch write enable as we are using positive clock latch register
    // to improve timing on the data read from the CPU.
    always @(negedge clk) begin
        if (!rstn) data_latch_wen <= 1;
        else data_latch_wen <= game_latch_sync[1];
    end

    latch_reg_p #(.WIDTH(24)) l_data (
        .clk(clk),
        .wen(data_latch_wen),
        .data_in(shift_reg),
        .data_out(data_reg)
    );

    assign controller_1 = data_reg[11:0];
    assign controller_2 = data_reg[23:12];

endmodule
