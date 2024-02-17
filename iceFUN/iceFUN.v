/*
 * Copyright (c) 2024 Michael Bell
 * SPDX-License-Identifier: Apache-2.0
 */

`define default_netname none

module tinyQV_top (
        input clk12MHz,
        input button1,
        input button2,
        input button3,
        input button4,
        output led1,
        output led2,
        output led3,
        output led4,
        output led5,
        output led6,
        output led7,
        output led8,
        output lcol1,
        output lcol2,
        output lcol3,
        output lcol4,
        
        input clk,
        input rst_n,

        inout flash_cs,
        inout [3:0] sd,
        inout sck,
        inout ram_a_cs,
        inout ram_b_cs,

        output uart_txd,
        input uart_rxd,
        output uart_rts

);

    // Register the reset on the negative edge of clock for safety.
    // This also allows the option of async reset in the design, which might be preferable in some cases
    reg rst_reg_n;
    always @(negedge clk) rst_reg_n <= rst_n;

    // Bidirs are used for SPI interface
    wire [3:0] qspi_data_in = sd;
    wire [3:0] qspi_data_out;
    wire [3:0] qspi_data_oe;
    wire       qspi_clk_out;
    wire       qspi_flash_select;
    wire       qspi_ram_a_select;
    wire       qspi_ram_b_select;
    
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin
            assign sd[i] = qspi_data_oe[i] ? qspi_data_out[i] : 1'bz;
        end
    endgenerate
    assign flash_cs = rst_n ? qspi_flash_select : 1'bz;
    assign sck =      rst_n ? qspi_clk_out : 1'bz;
    assign ram_a_cs = rst_n ? qspi_ram_a_select : 1'bz;
    assign ram_b_cs = rst_n ? qspi_ram_b_select : 1'bz;

    wire [27:0] addr;
    wire  [1:0] write_n;
    wire  [1:0] read_n;
/*verilator lint_off UNUSEDSIGNAL*/
    wire [31:0] data_to_write;  // Currently only bottom byte used.
/*verilator lint_on UNUSEDSIGNAL*/

    wire        data_ready;
    reg [31:0] data_from_read;

    tinyQV i_tinyqv(
        .clk(clk),
        .rstn(rst_reg_n),

        .data_addr(addr),
        .data_write_n(write_n),
        .data_read_n(read_n),
        .data_out(data_to_write),

        .data_ready(data_ready),
        .data_in(data_from_read),

        .spi_data_in(qspi_data_in),
        .spi_data_out(qspi_data_out),
        .spi_data_oe(qspi_data_oe),
        .spi_clk_out(qspi_clk_out),
        .spi_flash_select(qspi_flash_select),
        .spi_ram_a_select(qspi_ram_a_select),
        .spi_ram_b_select(qspi_ram_b_select)
    );

    // Address to peripheral map
    localparam PERI_NONE = 0;
    localparam PERI_GPIO_OUT = 2;
    localparam PERI_GPIO_IN = 3;
    localparam PERI_UART = 4;
    localparam PERI_UART_STATUS = 5;

    reg [2:0] connect_peripheral;

    always @(*) begin
        if (addr == 28'h8000000) connect_peripheral = PERI_GPIO_OUT;
        else if (addr == 28'h8000004) connect_peripheral = PERI_GPIO_IN;
        else if (addr == 28'h8000010) connect_peripheral = PERI_UART;
        else if (addr == 28'h8000014) connect_peripheral = PERI_UART_STATUS;
        else connect_peripheral = PERI_NONE;
    end

    // All transactions complete immediately
    assign data_ready = 1'b1;

    // Read data
    always @(*) begin
        case (connect_peripheral)
            PERI_GPIO_OUT:    data_from_read = gpio_out;
            PERI_GPIO_IN:     data_from_read = {28'h0, button4, button3, button2, button1};
            PERI_UART:        data_from_read = {24'h0, uart_rx_data};
            PERI_UART_STATUS: data_from_read = {30'h0, uart_rx_valid, uart_tx_busy};
            default:          data_from_read = 32'hFFFF_FFFF;
        endcase
    end

    // GPIO Out
    reg [31:0] gpio_out;
    always @(posedge clk) begin
        if (!rst_reg_n) gpio_out <= 0;
        if (write_n != 2'b11 && connect_peripheral == PERI_GPIO_OUT) begin
            if (write_n == 2'b10) gpio_out <= data_to_write;
            else if (write_n == 2'b01) gpio_out[15:0] <= data_to_write[15:0];
            else if (write_n == 2'b00) gpio_out[7:0] <= data_to_write[7:0];
        end
    end

    // UART
    wire uart_tx_busy;
    wire uart_rx_valid;
    wire [7:0] uart_rx_data;
    wire uart_tx_start = write_n != 2'b11 && connect_peripheral == PERI_UART;

    uart_tx #(.CLK_HZ(32_000_000), .BIT_RATE(115_200)) i_uart_tx(
        .clk(clk),
        .resetn(rst_reg_n),
        .uart_txd(uart_txd),
        .uart_tx_en(uart_tx_start),
        .uart_tx_data(data_to_write[7:0]),
        .uart_tx_busy(uart_tx_busy) 
    );

    uart_rx #(.CLK_HZ(32_000_000), .BIT_RATE(115_200)) i_uart_rx(
        .clk(clk),
        .resetn(rst_reg_n),
        .uart_rxd(uart_rxd),
        .uart_rts(uart_rts),
        .uart_rx_read(connect_peripheral == PERI_UART && read_n != 2'b11),
        .uart_rx_valid(uart_rx_valid),
        .uart_rx_data(uart_rx_data) 
    );

    // GPIO on LEDs
    wire [7:0] leds1_7seg = gpio_out[31:24];
    wire [7:0] leds2_7seg = gpio_out[23:16];
    wire [7:0] leds3_7seg = gpio_out[15:8];
    wire [7:0] leds4_7seg = gpio_out[7:0];

    // map the output of ledscan to the port pins
    wire [7:0] leds_out;
    wire [3:0] lcol;
    assign { led8, led7, led6, led5, led4, led3, led2, led1 } = leds_out[7:0];
    assign { lcol4, lcol3, lcol2, lcol1 } = lcol[3:0];

    LedScan scan (
                .clk12MHz(clk12MHz),
                .leds1(leds1_7seg),
                .leds2(leds2_7seg),
                .leds3(leds3_7seg),
                .leds4(leds4_7seg),
                .leds(leds_out),
                .lcol(lcol)
        );    

endmodule
