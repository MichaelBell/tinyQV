/* Copyright 2023 (c) Michael Bell

   A QSPI read-only flash controller

   Note this is no longer used by TinyQV, but is a reasonable reference
   for a QSPI flash controller.
   
   The QSPI clock is driven at half the frequency of the project clock.  It
   does not have any latency configuration, but given the latency of the mux 
   in TT06+ it should work up to about 60MHz project clock (30MHz QSPI clock),
   which is around the limit of the TT outputs anyway.
   
   To start reading:
   - Set addr_in and set start_read high for 1 cycle
   - Data is available on data_out on each cycle that data_ready is high
   - Set stall_read high to stall the clock the next time data is ready,
     data_ready will not clear while stall_read is high - the data remains available.
   - Set stop_read high to cancel the read.

   If the controller is configured to transfer multiple bytes, then
   note that the word transferred in data_in/data_out is in big
   endian order, i.e. the byte with the lowest address is aligned to 
   the MSB of the word. 
   */
module qspi_flash_controller #(parameter DATA_WIDTH_BYTES=2, parameter ADDR_BITS=24) (
    input clk,
    input rstn,

    // External SPI interface
    input      [3:0] spi_data_in,
    output     [3:0] spi_data_out,
    output reg [3:0] spi_data_oe,
    output           spi_select,
    output reg       spi_clk_out,

    // Internal interface for reading/writing data
    input [ADDR_BITS-1:0]           addr_in,
    input                           start_read,
    input                           stall_read,
    input                           stop_read,

    output [DATA_WIDTH_BYTES*8-1:0] data_out,
    output reg                      data_ready,
    output                          busy
);


`define max(a, b) ((a > b) ? a : b)

    localparam DATA_WIDTH_BITS = DATA_WIDTH_BYTES * 8;

    localparam FSM_IDLE = 0;
    localparam FSM_CMD  = 1;
    localparam FSM_ADDR = 2;
    localparam FSM_DUMMY1 = 3;
    localparam FSM_DUMMY2 = 4;
    localparam FSM_DATA = 5;
    localparam FSM_STALLED = 6;

    reg [2:0] fsm_state;
    reg [ADDR_BITS-1:0]       addr;
    reg [DATA_WIDTH_BITS-1:0] data;
    reg [$clog2(`max(DATA_WIDTH_BITS,`max(ADDR_BITS,31)))-3:0] nibbles_remaining;

    assign data_out = data;
    assign busy = fsm_state != FSM_IDLE;

/* Assignments to nibbles_remaining are not easy to give the correct width for */
/* verilator lint_off WIDTH */

    always @(posedge clk) begin
        if (!rstn || stop_read) begin
            fsm_state <= FSM_IDLE;
            nibbles_remaining <= 0;
            data_ready <= 0;
            spi_clk_out <= 1;
            spi_data_oe <= 4'b0000;
        end else begin
            data_ready <= 0;
            if (fsm_state == FSM_IDLE) begin
                if (start_read) begin
                    fsm_state <= FSM_CMD;
                    nibbles_remaining <= 8-1;
                    spi_data_oe <= 4'b0001;
                    spi_clk_out <= 0;
                end
            end else begin
                if (fsm_state == FSM_STALLED) begin
                    data_ready <= 1;
                    if (!stall_read) fsm_state <= FSM_DATA;
                end else begin
                    spi_clk_out <= !spi_clk_out;
                    if (spi_clk_out) begin
                        if (nibbles_remaining == 0) begin
                            if (fsm_state == FSM_DATA) begin
                                data_ready <= 1;
                                nibbles_remaining <= (DATA_WIDTH_BITS >> 2)-1;
                                if (stall_read) fsm_state <= FSM_STALLED;
                            end else begin
                                fsm_state <= fsm_state + 1;
                                if (fsm_state == FSM_CMD) begin
                                    nibbles_remaining <= (ADDR_BITS >> 2)-1;
                                    spi_data_oe <= 4'b1111;
                                end
                                else if (fsm_state == FSM_ADDR) begin
                                    nibbles_remaining <= 2-1;
                                end
                                else if (fsm_state == FSM_DUMMY1) begin
                                    spi_data_oe <= 4'b0000;
                                    nibbles_remaining <= 4-1;
                                end
                                else if (fsm_state == FSM_DUMMY2) begin
                                    nibbles_remaining <= (DATA_WIDTH_BITS >> 2)-1;
                                end
                            end
                        end else begin
                            nibbles_remaining <= nibbles_remaining - 1;
                        end
                    end
                end
            end
        end
    end

    always @(posedge clk) begin
        if (fsm_state == FSM_IDLE && start_read) begin
            addr <= addr_in;
        end else if (fsm_state == FSM_ADDR && spi_clk_out) begin
            addr <= {addr[ADDR_BITS-5:0], 4'b0000};
        end
    end

    always @(posedge clk) begin
        if (fsm_state == FSM_DATA && spi_clk_out) begin
            data <= {data[DATA_WIDTH_BITS-5:0], spi_data_in};
        end
    end

    assign spi_select = fsm_state == FSM_IDLE;

    assign spi_data_out = fsm_state == FSM_CMD  ? {3'b000, !(nibbles_remaining == 4 || nibbles_remaining == 2)} :
                          fsm_state == FSM_ADDR ? addr[ADDR_BITS-1:ADDR_BITS-4] :
                                                  4'b0001;
/* verilator lint_on WIDTH */

endmodule
