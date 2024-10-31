/* Copyright 2024 (c) Michael Bell
   SPDX-License-Identifier: Apache-2.0

   A very simple 8-bit PWM peripheral
   */

module pwm_ctrl (
    input clk,
    input rstn,

    // PWM out
    output       pwm,

    // Configuration
    input  [7:0] level,     // PWM level, read when set_leevl is high
    input        set_level
);

    reg [7:0] pwm_level;
    reg [7:0] pwm_count;

    always @(posedge clk) begin
        if (!rstn) begin
            pwm_level <= 0;
            pwm_count <= 0;
        end else begin
            // Wrap at 254 so that a level of 0-255 goes from always off to always on.
            pwm_count <= pwm_count + 1;
            if (pwm_count == 8'hfe) pwm_count <= 8'h00;

            if (set_level) pwm_level <= level;
        end
    end

    assign pwm = pwm_count < pwm_level;

endmodule
