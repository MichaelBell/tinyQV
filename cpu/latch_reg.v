`default_nettype none

// A wrapper to use a latch as a register
// Note no reset - reset using data
module latch_reg_n #(
    parameter WIDTH=8
) (
    input wire clk,

    input wire wen,                 // Write enable
    input wire [WIDTH-1:0] data_in, // Data to write during second half of clock when wen is high

    output wire [WIDTH-1:0] data_out
);

`ifdef SIM
    reg [WIDTH-1:0] state;

    reg latched_wen;

    // Simulate clock gate: wen is latched when clock is high.
    always @(clk or wen)
        if (clk) latched_wen <= wen;

    /* verilator lint_off SYNCASYNCNET */
    always @(clk or latched_wen or data_in) begin
        if (!clk && latched_wen) state <= data_in;
    end
    /* verilator lint_on SYNCASYNCNET */

    assign data_out = state;

`elsif SCL_sky130_fd_sc_hd
    wire clk_b;
    wire gated_clk;

    // Lint for sky130 cells expects power pins, so disable the warning
    /* verilator lint_off PINMISSING */
    sky130_fd_sc_hd__clkinv_1 CLKINV(.Y(clk_b), .A(clk));

    /* verilator lint_off GENUNNAMED */
    generate
        if (WIDTH <= 6)
            sky130_fd_sc_hd__dlclkp_1 CG( .CLK(clk_b), .GCLK(gated_clk), .GATE(wen) );
        else if (WIDTH <= 12)
            sky130_fd_sc_hd__dlclkp_2 CG( .CLK(clk_b), .GCLK(gated_clk), .GATE(wen) );
        else
            sky130_fd_sc_hd__dlclkp_4 CG( .CLK(clk_b), .GCLK(gated_clk), .GATE(wen) );
    endgenerate
    /* verilator lint_on GENUNNAMED */

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i+1) begin : gen_latch
            sky130_fd_sc_hd__dlxtp_1 state (.Q(data_out[i]), .D(data_in[i]), .GATE(gated_clk) );
        end
    endgenerate
    /* verilator lint_on PINMISSING */
`else
    reg [WIDTH-1:0] state;
    always @(negedge clk) begin
        if (wen) state <= data_in;
    end

    assign data_out = state;
`endif

endmodule

module latch_reg_p #(
    parameter WIDTH=8
) (
    input wire clk,

    input wire wen,                 // Write enable
    input wire [WIDTH-1:0] data_in, // Data to write during second half of clock when wen is high

    output wire [WIDTH-1:0] data_out
);

`ifdef SIM
    reg [WIDTH-1:0] state;

    reg latched_wen;

    // Simulate clock gate: wen is latched when clock is low.
    always @(clk or wen)
        if (!clk) latched_wen <= wen;

    /* verilator lint_off SYNCASYNCNET */
    always @(clk or latched_wen or data_in) begin
        if (clk && latched_wen) state <= data_in;
    end
    /* verilator lint_on SYNCASYNCNET */

    assign data_out = state;

`elsif SCL_sky130_fd_sc_hd
    wire gated_clk;

    // Lint for sky130 cells expects power pins, so disable the warning
    /* verilator lint_off PINMISSING */
    /* verilator lint_off GENUNNAMED */
    generate
        if (WIDTH <= 6)
            sky130_fd_sc_hd__dlclkp_1 CG( .CLK(clk), .GCLK(gated_clk), .GATE(wen) );
        else if (WIDTH <= 12)
            sky130_fd_sc_hd__dlclkp_2 CG( .CLK(clk), .GCLK(gated_clk), .GATE(wen) );
        else
            sky130_fd_sc_hd__dlclkp_4 CG( .CLK(clk), .GCLK(gated_clk), .GATE(wen) );
    endgenerate
    /* verilator lint_on GENUNNAMED */

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i+1) begin : gen_latch
            sky130_fd_sc_hd__dlxtp_1 state (.Q(data_out[i]), .D(data_in[i]), .GATE(gated_clk) );
        end
    endgenerate
    /* verilator lint_on PINMISSING */
`else
    reg [WIDTH-1:0] state;
    always @(posedge clk) begin
        if (wen) state <= data_in;
    end

    assign data_out = state;
`endif

endmodule

module latch_reg32_n (
    input wire clk,

    input wire wen,                 // Write enable
    input wire [31:0] data_in,      // Data to write during second half of clock when wen is high

    output wire [31:0] data_out
);

    latch_reg_n #(.WIDTH(16)) l_lo (
        .clk(clk),
        .wen(wen),
        .data_in(data_in[15:0]),
        .data_out(data_out[15:0])
    );

    latch_reg_n #(.WIDTH(16)) l_hi (
        .clk(clk),
        .wen(wen),
        .data_in(data_in[31:16]),
        .data_out(data_out[31:16])
    );

endmodule

module latch_reg32_p (
    input wire clk,

    input wire wen,                 // Write enable
    input wire [31:0] data_in,      // Data to write during second half of clock when wen is high

    output wire [31:0] data_out
);

    latch_reg_p #(.WIDTH(16)) l_lo (
        .clk(clk),
        .wen(wen),
        .data_in(data_in[15:0]),
        .data_out(data_out[15:0])
    );

    latch_reg_p #(.WIDTH(16)) l_hi (
        .clk(clk),
        .wen(wen),
        .data_in(data_in[31:16]),
        .data_out(data_out[31:16])
    );

endmodule
