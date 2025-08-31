/*
 * Copyright (c) 2024 Michael Bell
 * SPDX-License-Identifier: Apache-2.0
 */

`define default_netname none

module tinyQV_top (
        input clk,
        input rst_n,

        inout flash_cs,
        inout [3:0] sd,
        inout sck,
        inout ram_a_cs,
        inout ram_b_cs,

        input [7:0] ui_in,
        output [7:0] uo_out

);
    localparam CLOCK_MHZ = 14;
    localparam CLOCK_FREQ = CLOCK_MHZ * 1_000_000;
    
    // Register the reset on the negative edge of clock for safety.
    // This also allows the option of async reset in the design, which might be preferable in some cases
    reg rst_reg_n;
    always @(negedge clk) rst_reg_n <= rst_n;

    // Bidirs are used for SPI interface
    wire [3:0] qspi_data_in;
    wire [3:0] qspi_data_out;
    wire [3:0] qspi_data_oe;
    wire       qspi_clk_out;
    wire       qspi_flash_select;
    wire       qspi_ram_a_select;
    wire       qspi_ram_b_select;
    wire       uio_out7;
    
    SB_IO #(
//		.PIN_TYPE(6'b 1101_00),  // Registered in, out and oe
		.PIN_TYPE(6'b 1010_01),
		.PULLUP(1'b 0)
    ) qspi_data [3:0] (
		.PACKAGE_PIN(sd),
        .OUTPUT_CLK(clk),
        .INPUT_CLK(clk),
		.OUTPUT_ENABLE(qspi_data_oe),
		.D_OUT_0(qspi_data_out),
		.D_IN_0(qspi_data_in)
	);
    SB_IO #(
//		.PIN_TYPE(6'b 1001_01),  // Registered out only
		.PIN_TYPE(6'b 1010_01),
		.PULLUP(1'b 0)
    ) qspi_pins [3:0] (
		.PACKAGE_PIN({flash_cs, sck, ram_a_cs, ram_b_cs}),
        .OUTPUT_CLK(clk),
		.OUTPUT_ENABLE({4{rst_n}}),
		.D_OUT_0({qspi_flash_select, qspi_clk_out, qspi_ram_a_select, uio_out7})
	);

    wire [27:0] addr;
    wire  [1:0] write_n;
    wire  [1:0] read_n;
    wire        read_complete;
/*verilator lint_off UNUSEDSIGNAL*/
    wire [31:0] data_to_write;  // Currently only bottom byte used.
/*verilator lint_on UNUSEDSIGNAL*/

    wire time_pulse;

    wire        data_ready;
    reg [31:0] data_from_read;

    wire       debug_instr_complete;
    wire       debug_instr_ready;
    wire       debug_instr_valid;
    wire       debug_fetch_restart;
    wire       debug_data_ready;
    wire       debug_interrupt_pending;
    wire       debug_branch;
    wire       debug_early_branch;
    wire       debug_ret;
    wire       debug_reg_wen;
    wire       debug_counter_0;
    wire       debug_data_continue;
    wire       debug_stall_txn;
    wire       debug_stop_txn;
    wire [3:0] debug_rd;

    tinyQV i_tinyqv(
        .clk(clk),
        .rstn(rst_reg_n),

        .data_addr(addr),
        .data_write_n(write_n),
        .data_read_n(read_n),
        .data_read_complete(read_complete),
        .data_out(data_to_write),

        .data_ready(data_ready),
        .data_in(data_from_read),

        .interrupt_req(interrupt_req),
        .time_pulse(time_pulse),

        .spi_data_in(qspi_data_in),
        .spi_data_out(qspi_data_out),
        .spi_data_oe(qspi_data_oe),
        .spi_clk_out(qspi_clk_out),
        .spi_flash_select(qspi_flash_select),
        .spi_ram_a_select(qspi_ram_a_select),
        .spi_ram_b_select(qspi_ram_b_select),

        .debug_instr_complete(debug_instr_complete),
        .debug_instr_ready(debug_instr_ready),
        .debug_instr_valid(debug_instr_valid),
        .debug_fetch_restart(debug_fetch_restart),
        .debug_data_ready(debug_data_ready),
        .debug_interrupt_pending(debug_interrupt_pending),
        .debug_branch(debug_branch),
        .debug_early_branch(debug_early_branch),
        .debug_ret(debug_ret),
        .debug_reg_wen(debug_reg_wen),
        .debug_counter_0(debug_counter_0),
        .debug_data_continue(debug_data_continue),
        .debug_stall_txn(debug_stall_txn),
        .debug_stop_txn(debug_stop_txn),
        .debug_rd(debug_rd)
    );

    // Peripheral IOs on ui_in and uo_out
    wire       spi_miso  = ui_in[2];
    wire       uart_rxd  = ui_in[7];

    wire       spi_cs;
    wire       spi_sck;
    wire       spi_mosi;
    wire       spi_dc;
    wire       uart_txd;
    wire       uart_rts;
    wire       debug_uart_txd;
    wire       debug_signal;
    wire       pwm_out;
    reg  [9:0] gpio_out_sel;
    reg  [7:0] gpio_out;

    assign uo_out[0] = gpio_out_sel[0] ? gpio_out[0] : uart_txd;
    assign uo_out[1] = gpio_out_sel[1] ? gpio_out[1] : uart_rts;
    assign uo_out[2] = gpio_out_sel[2] ? gpio_out[2] : 
                       debug_register_data ? debug_rd_r[0] : spi_dc;
    assign uo_out[3] = gpio_out_sel[3] ? gpio_out[3] : 
                       debug_register_data ? debug_rd_r[1] : spi_mosi;
    assign uo_out[4] = gpio_out_sel[4] ? gpio_out[4] : 
                       debug_register_data ? debug_rd_r[2] : spi_cs;
    assign uo_out[5] = gpio_out_sel[5] ? gpio_out[5] : 
                       debug_register_data ? debug_rd_r[3] : spi_sck;
    assign uo_out[6] = gpio_out_sel[6] ? gpio_out[6] : debug_uart_txd;
    assign uo_out[7] = gpio_out_sel[8] ? pwm_out :
                       gpio_out_sel[7] ? gpio_out[7] : debug_signal;
    assign uio_out7 = gpio_out_sel[9] ? pwm_out : qspi_ram_b_select;

    // Address to peripheral map
    localparam PERI_NONE = 4'hF;
    localparam PERI_GPIO_OUT = 4'h0;
    localparam PERI_GPIO_IN = 4'h1;
    localparam PERI_GPIO_OUT_SEL = 4'h3;
    localparam PERI_UART = 4'h4;
    localparam PERI_UART_STATUS = 4'h5;
    localparam PERI_DEBUG_UART = 4'h6;
    localparam PERI_DEBUG_UART_STATUS = 4'h7;
    localparam PERI_SPI = 4'h8;
    localparam PERI_SPI_STATUS = 4'h9;
    localparam PERI_PWM = 4'hA;
    localparam PERI_DEBUG = 4'hC;

    reg [3:0] connect_peripheral;
    always @(*) begin
        if ({addr[27:6], addr[1:0]} == 24'h800000) 
            connect_peripheral = addr[5:2];
        else
            connect_peripheral = PERI_NONE;
    end

    // All transactions complete immediately
    assign data_ready = 1'b1;

    // Interrupt requests
    reg [1:0] ui_in_reg;
    always @(posedge clk) begin
        ui_in_reg <= ui_in[1:0];
    end
    wire [3:0] interrupt_req = {!uart_tx_busy, uart_rx_valid, ui_in_reg[1:0]};

    // Read data
    always @(*) begin
        case (connect_peripheral)
            PERI_GPIO_OUT:    data_from_read = {24'h0, uo_out};
            PERI_GPIO_IN:     data_from_read = {24'h0, ui_in};
            PERI_GPIO_OUT_SEL:data_from_read = {22'h0, gpio_out_sel};
            PERI_UART:        data_from_read = {24'h0, uart_rx_data};
            PERI_UART_STATUS: data_from_read = {30'h0, uart_rx_valid, uart_tx_busy};
            PERI_DEBUG_UART_STATUS: data_from_read = {31'h0, debug_uart_tx_busy};
            PERI_SPI:         data_from_read = {24'h0, spi_data};
            PERI_SPI_STATUS:  data_from_read = {31'h0, spi_busy};
            default:          data_from_read = 32'hFFFF_FFFF;
        endcase
    end

    // GPIO Out
    always @(posedge clk) begin
        if (!rst_reg_n) begin
            gpio_out_sel <= 0;
            gpio_out <= 0;
        end
        if (write_n != 2'b11) begin
            if (connect_peripheral == PERI_GPIO_OUT) gpio_out <= data_to_write[7:0];
            if (connect_peripheral == PERI_GPIO_OUT_SEL) gpio_out_sel <= data_to_write[9:0];
        end
    end

    // UART
    wire uart_tx_busy;
    wire uart_rx_valid;
    wire [7:0] uart_rx_data;
    wire uart_tx_start = write_n != 2'b11 && connect_peripheral == PERI_UART;

    uart_tx #(.CLK_HZ(CLOCK_FREQ), .BIT_RATE(115_200)) i_uart_tx(
        .clk(clk),
        .resetn(rst_reg_n),
        .uart_txd(uart_txd),
        .uart_tx_en(uart_tx_start),
        .uart_tx_data(data_to_write[7:0]),
        .uart_tx_busy(uart_tx_busy) 
    );

    uart_rx #(.CLK_HZ(CLOCK_FREQ), .BIT_RATE(115_200)) i_uart_rx(
        .clk(clk),
        .resetn(rst_reg_n),
        .uart_rxd(uart_rxd),
        .uart_rts(uart_rts),
        .uart_rx_read(connect_peripheral == PERI_UART && read_complete),
        .uart_rx_valid(uart_rx_valid),
        .uart_rx_data(uart_rx_data) 
    );

    // Debug UART - runs fast to reduce the width of the count necessary for the divider!
    wire debug_uart_tx_busy;
    wire debug_uart_tx_start = write_n != 2'b11 && connect_peripheral == PERI_DEBUG_UART;

    uart_tx #(.CLK_HZ(CLOCK_FREQ), .BIT_RATE(1_000_000)) i_debug_uart_tx(
        .clk(clk),
        .resetn(rst_reg_n),
        .uart_txd(debug_uart_txd),
        .uart_tx_en(debug_uart_tx_start),
        .uart_tx_data(data_to_write[7:0]),
        .uart_tx_busy(debug_uart_tx_busy) 
    );

    // Time
    reg [5:0] time_count;

    generate
        if (CLOCK_MHZ == 64) begin
            always @(posedge clk) begin
                if (!rst_reg_n) begin
                    time_count <= 0;
                end else begin
                    time_count <= time_count + 1;
                end
            end
        end else begin
            always @(posedge clk) begin
                if (!rst_reg_n) begin
                    time_count <= 0;
                end else begin
                    if (time_count == (CLOCK_MHZ - 1)) time_count <= 0;
                    else time_count <= time_count + 1;
                end
            end
        end
    endgenerate
    assign time_pulse = time_count == (CLOCK_MHZ - 1);

    // SPI
    wire spi_start = write_n != 2'b11 && connect_peripheral == PERI_SPI;
    wire [7:0] spi_data;
    wire spi_busy;

    spi_ctrl i_spi(
        .clk(clk),
        .rstn(rst_reg_n),

        .spi_miso(spi_miso),
        .spi_select(spi_cs),
        .spi_clk_out(spi_sck),
        .spi_mosi(spi_mosi),
        .spi_dc(spi_dc),

        .dc_in(data_to_write[9]),
        .end_txn(data_to_write[8]),
        .data_in(data_to_write[7:0]),
        .start(spi_start),
        .data_out(spi_data),
        .busy(spi_busy),

        .set_config(connect_peripheral == PERI_SPI_STATUS && write_n != 2'b11),
        .divider_in(data_to_write[1:0]),
        .read_latency_in(data_to_write[2])
    );

    pwm_ctrl i_pwm(
        .clk(clk),
        .rstn(rst_reg_n),

        .pwm(pwm_out),

        .level(data_to_write[7:0]),
        .set_level(connect_peripheral == PERI_PWM && write_n != 2'b11)
    );    

    // Debug
    reg debug_register_data;
    always @(posedge clk) begin
        if (!rst_reg_n)
            debug_register_data <= 1'b0;
        else if (write_n != 2'b11 && connect_peripheral == PERI_DEBUG)
            debug_register_data <= data_to_write[0];
    end

    reg [3:0] debug_rd_r;
    always @(posedge clk) begin
        debug_rd_r <= debug_rd;
    end

/*
    reg [15:0] debug_signals;
    always @(*) begin
        debug_signals  = {debug_instr_complete,
                          debug_instr_ready,
                          debug_instr_valid,
                          debug_fetch_restart,
                          read_n != 2'b11,
                          write_n != 2'b11,
                          debug_data_ready,
                          debug_interrupt_pending,
                          debug_branch,
                          debug_early_branch,
                          debug_ret,
                          debug_reg_wen,
                          debug_counter_0,
                          debug_data_continue,
                          debug_stall_txn,
                          debug_stop_txn};
    end
    assign debug_signal = debug_signals[ui_in[6:3]];
*/
    assign debug_signal = 1'b0;

endmodule
