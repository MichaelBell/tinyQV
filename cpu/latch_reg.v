`default_nettype none

// A wrapper to use a latch as a register
// Note no reset - reset using data
module latch_reg #(
    parameter WIDTH=8
) (
    input wire clk,

    input wire wen,                 // Write enable
    input wire [WIDTH-1:0] data_in, // Data to write during second half of clock when wen is high

    output wire [WIDTH-1:0] data_out
);

`ifdef SIM
    reg [WIDTH-1:0] state;
    always @(clk or wen or data_in) begin
        if (!clk && wen) state <= data_in;
    end

    assign data_out = state;

`else
`ifdef ICE40
    reg [WIDTH-1:0] state;
    always @(posedge clk) begin
        if (wen) state <= data_in;
    end

    assign data_out = state;

`else
    wire clk_b;
    wire gated_clk;

    // Lint for sky130 cells expects power pins, so disable the warning
    /* verilator lint_off PINMISSING */
    sky130_fd_sc_hd__inv_1 CLKINV(.Y(clk_b), .A(clk));

    generate
        if (WIDTH <= 6)
            sky130_fd_sc_hd__dlclkp_1 CG( .CLK(clk_b), .GCLK(gated_clk), .GATE(wen) );
        else if (WIDTH <= 12)
            sky130_fd_sc_hd__dlclkp_2 CG( .CLK(clk_b), .GCLK(gated_clk), .GATE(wen) );
        else
            sky130_fd_sc_hd__dlclkp_4 CG( .CLK(clk_b), .GCLK(gated_clk), .GATE(wen) );
    endgenerate

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i+1) begin
            sky130_fd_sc_hd__dlxtp_1 state (.Q(data_out[i]), .D(data_in[i]), .GATE(gated_clk) );
        end
    endgenerate
    /* verilator lint_on PINMISSING */
`endif
`endif

endmodule
