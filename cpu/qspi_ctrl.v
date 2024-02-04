/* Copyright 2023 (c) Michael Bell

   A QSPI controller for the QSPI PMOD:
     https://github.com/mole99/qspi-pmod
   
   To start reading:
   - Set addr_in and set start_read high for 1 cycle
   - Data is available on data_out on each cycle that data_ready is high
   - Set stall_txn high to stall the clock the next time data is ready,
     data_ready will not clear while stall_read is high - the data remains available.
   - Set stop_txn high to cancel the read.

   To start writing:
   - Set addr_in, data_in and set start_write high for 1 cycle
   - Update data_in each cycle data_req goes high to continue writing,
   - if data is not ready the clock can be temporarily stalled with stall_txn,
   - Or set stop_txn high to cancel the write.

   */
module qspi_controller (
    input clk,
    input rstn,

    // External SPI interface
    input      [3:0] spi_data_in,
    output     [3:0] spi_data_out,
    output reg [3:0] spi_data_oe,
    output reg       spi_clk_out,

    output reg       spi_flash_select,
    output reg       spi_ram_a_select,
    output reg       spi_ram_b_select,

    // Internal interface for reading/writing data
    // Address map is:
    //  0x0000000 - 0x0FFFFFF: Flash
    //  0x1000000 - 0x17FFFFF: RAM A
    //  0x1800000 - 0x1FFFFFF: RAM B
    input [24:0] addr_in,
    input  [7:0] data_in,
    input        start_read,
    input        start_write,
    input        stall_txn,
    input        stop_txn,

    output [7:0] data_out,
    output reg   data_req,
    output reg   data_ready,
    output       busy
);


`define max(a, b) ((a > b) ? a : b)

    localparam ADDR_BITS = 24;
    localparam DATA_WIDTH_BITS = 8;

    localparam FSM_IDLE = 0;
    localparam FSM_CMD  = 1;
    localparam FSM_ADDR = 2;
    localparam FSM_DUMMY1 = 3;
    localparam FSM_DUMMY2 = 4;
    localparam FSM_DATA = 5;
    localparam FSM_STALLED = 6;

    reg [2:0] fsm_state;
    reg       is_writing;
    reg [ADDR_BITS-1:0]       addr;
    reg [DATA_WIDTH_BITS-1:0] data;
    reg [$clog2(`max(DATA_WIDTH_BITS,`max(ADDR_BITS,31)))-3:0] nibbles_remaining;

    assign data_out = data;
    assign busy = fsm_state != FSM_IDLE;

/* Assignments to nibbles_remaining are not easy to give the correct width for */
/* verilator lint_off WIDTHTRUNC */

    always @(posedge clk) begin
        if (!rstn || stop_txn) begin
            fsm_state <= FSM_IDLE;
            is_writing <= 0;
            nibbles_remaining <= 0;
            data_ready <= 0;
            spi_clk_out <= 1;
            spi_data_oe <= 4'b0000;
            spi_flash_select <= 1;
            spi_ram_a_select <= 1;
            spi_ram_b_select <= 1;
            data_req <= 0;
        end else begin
            data_ready <= 0;
            data_req <= 0;
            if (fsm_state == FSM_IDLE) begin
                if (start_read || start_write) begin
                    fsm_state <= FSM_CMD;
                    is_writing <= !start_read && addr_in[24];  // Only writes to RAM supported.
                    nibbles_remaining <= 8-1;
                    spi_data_oe <= 4'b0001;
                    spi_clk_out <= 0;
                    spi_flash_select <= addr_in[24];
                    spi_ram_a_select <= addr_in[24:23] != 2'b10;
                    spi_ram_b_select <= addr_in[24:23] != 2'b11;
                end
            end else begin
                if (fsm_state == FSM_STALLED) begin
                    data_ready <= !is_writing;
                    if (!stall_txn) fsm_state <= FSM_DATA;
                end else begin
                    spi_clk_out <= !spi_clk_out;
                    if (spi_clk_out) begin
                        if (nibbles_remaining == 0) begin
                            if (fsm_state == FSM_DATA) begin
                                data_ready <= !is_writing;
                                nibbles_remaining <= (DATA_WIDTH_BITS >> 2)-1;
                                if (stall_txn) fsm_state <= FSM_STALLED;
                            end else begin
                                fsm_state <= fsm_state + 1;
                                if (fsm_state == FSM_CMD) begin
                                    nibbles_remaining <= (ADDR_BITS >> 2)-1;
                                    spi_data_oe <= 4'b1111;
                                end
                                else if (fsm_state == FSM_ADDR) begin
                                    if (is_writing) begin
                                        fsm_state <= FSM_DATA;
                                        spi_data_oe <= 4'b1111;
                                        nibbles_remaining <= (DATA_WIDTH_BITS >> 2)-1;
                                    end else begin
                                        nibbles_remaining <= 2-1;
                                    end
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
                    end else begin
                        data_req <= is_writing && (fsm_state == FSM_DATA) && nibbles_remaining == 0;
                    end
                end
            end
        end
    end

    always @(posedge clk) begin
        if (fsm_state == FSM_IDLE && (start_read || start_write)) begin
            addr <= addr_in[23:0];
        end else if (fsm_state == FSM_ADDR && spi_clk_out) begin
            addr <= {addr[ADDR_BITS-5:0], 4'b0000};
        end
    end

    always @(posedge clk) begin
        if (is_writing) begin
            if (spi_clk_out) begin
                if (nibbles_remaining == 0 || fsm_state == FSM_STALLED) begin
                    data <= data_in;
                end else if (fsm_state == FSM_DATA) begin
                    data <= {data[DATA_WIDTH_BITS-5:0], spi_data_in};
                end
            end
        end else if (!spi_clk_out && fsm_state == FSM_DATA) begin
            data <= {data[DATA_WIDTH_BITS-5:0], spi_data_in};
        end
    end

    assign spi_data_out = fsm_state == FSM_CMD  ? {3'b000, is_writing ? (nibbles_remaining == 5 || nibbles_remaining == 4 || nibbles_remaining == 3) : !(nibbles_remaining == 4 || nibbles_remaining == 2)} :
                          fsm_state == FSM_ADDR ? addr[ADDR_BITS-1:ADDR_BITS-4] :
                          fsm_state == FSM_DATA ? data[DATA_WIDTH_BITS-1:DATA_WIDTH_BITS-4] :
                                                  4'b1111;
/* verilator lint_on WIDTHTRUNC */

endmodule
