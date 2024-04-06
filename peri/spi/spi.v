/* Copyright 2023-2024 (c) Michael Bell
   SPDX-License-Identifier: Apache-2.0

   A general SPI controller, with optional DC line for
   simple control of SPI LCDs.
   */

module spi_ctrl (
    input clk,
    input rstn,

    // External SPI interface
    input      spi_miso,
    output reg spi_select,
    output reg spi_clk_out,
    output     spi_mosi,
    output reg spi_dc,  // Data/command indication

    // Internal interface for reading/writing data
    input        dc_in,    // Written back to spi_dc when byte transmission begins
    input        end_txn,  // Whether to release CS at the end of this byte
    input  [7:0] data_in,  // Data to transmit
    input        start,    // Signal to start a transfer, set high for 1 clock when busy is low
    output [7:0] data_out, // Data read, valid when busy is low
    output reg   busy,     // Whether a transfer is in progress

    // Configuration
    input        set_config,  // Set high to change the clock divider
    input  [1:0] divider_in,  // SPI clock is input clock divided by 2 * (divider_in + 1)
    input        read_latency_in // If low reads are sampled half an SPI clock cycle after the rising edge, 
                                 // if high the sample is one SPI clock cycle later.
);

    reg [7:0] data;
    reg [3:0] bits_remaining;
    reg       end_txn_reg;
    reg [1:0] clock_count;
    reg [1:0] clock_divider;
    reg       read_latency;

    always @(posedge clk) begin
        if (!rstn) begin
            busy <= 0;
            spi_select <= 1;
            spi_clk_out <= 0;
            clock_count <= 0;
            bits_remaining <= 0;
        end else begin
            if (!busy) begin
                if (start) begin
                    busy <= 1;
                    data <= data_in;
                    spi_dc <= dc_in;
                    end_txn_reg <= end_txn;
                    bits_remaining <= 4'd8;
                    spi_select <= 0;
                    spi_clk_out <= 0;
                end
            end else begin
                clock_count <= clock_count + 2'b01;
                if (clock_count == clock_divider) begin
                    clock_count <= 0;
                    spi_clk_out <= !spi_clk_out;
                    if (spi_clk_out) begin
                        data <= {data[6:0], spi_miso};
                        if (bits_remaining != 0) begin
                            bits_remaining <= bits_remaining - 3'b001;
                        end
                    end else begin
                        if (bits_remaining[3] == 0 && read_latency) data[0] <= spi_miso;
                        if (bits_remaining == 0) begin
                            busy <= 0;
                            spi_select <= end_txn_reg;
                            spi_clk_out <= 0;
                        end
                    end
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            clock_divider <= 1;
            read_latency <= 0;
        end else if (set_config) begin
            clock_divider <= divider_in;
            read_latency <= read_latency_in;
        end
    end

    assign spi_mosi = data[7];
    assign data_out = data;

endmodule
