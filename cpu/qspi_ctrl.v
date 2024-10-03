/* Copyright 2023-2024 (c) Michael Bell
   SPDX-License-Identifier: Apache-2.0

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
   - Update data_in each cycle data_req goes high to continue writing, on the cycle data_req is high.
   - if data is not ready the clock can be temporarily stalled with stall_txn,
   - Or set stop_txn high to cancel the write.

   Round trip latency of the TT mux is a little over 20ns, so we need configurable 
   delay cycles for reads to reach faster clock speeds.  The delay is configured
   by setting spi_data_in[2:0] to the number of additional read delay cycles and 
   clocking the controller while in reset.  Care must be taken bringing the design 
   out of reset to ensure the configuration is not accidentally modified.
   Note that tinyQV's reset is latched on the negative edge of clk, so reset must be 
   released while clock is high.
   Valid values of latency are 0 - 5:
   - 0: data is ready by the falling edge of the SPI clock immediately following the
           last dummy cycle
   - 1: data is ready by the rising edge of the next SPI clock (this is "normal")
   - 2-5: read the data delayed by further half SPI clock cycles. 

   */
module qspi_controller (
    input clk,
    input rstn,

    // External SPI interface
    input      [3:0] spi_data_in,
    output reg [3:0] spi_data_out,
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
    localparam DATA_WIDTH_BITS = 8;  // Note: This width is assumed by the latency implementation.

    localparam FSM_IDLE = 0;
    localparam FSM_CMD  = 1;
    localparam FSM_ADDR = 2;
    localparam FSM_DUMMY1 = 3;
    localparam FSM_DUMMY2 = 4;
    localparam FSM_DATA = 5;
    localparam FSM_STALLED = 6;
    localparam FSM_STALL_RECOVER = 7;

    reg [2:0] fsm_state;
    reg       is_writing;
    reg [ADDR_BITS-1:0]       addr;
    reg [DATA_WIDTH_BITS-1:0] data;
    reg [2:0] nibbles_remaining;
    reg [2:0] delay_cycles_cfg;
    reg [7:0] spi_in_buffer;

    assign data_out = data;
    assign busy = fsm_state != FSM_IDLE;

    reg stop_txn_reg;
    wire stop_txn_now = stop_txn_reg || (stop_txn && (!is_writing || spi_clk_out));
    always @(posedge clk) begin
        if (!rstn) 
            stop_txn_reg <= 0;
        else
            stop_txn_reg <= stop_txn && !stop_txn_now;
    end

    reg [2:0] read_cycles_count;

    reg last_ram_a_sel;
    reg last_ram_b_sel;
    wire ram_a_block = (last_ram_a_sel == 0) && addr_in[24:23] == 2'b10;
    wire ram_b_block = (last_ram_b_sel == 0) && addr_in[24:23] == 2'b11;

    always @(posedge clk) begin
        if (!rstn) begin
            delay_cycles_cfg <= spi_data_in[2:0];
        end
    end

/* Assignments to nibbles_remaining are not easy to give the correct width for */
/* verilator lint_off WIDTH */

    always @(posedge clk) begin
        if (!rstn || stop_txn_now) begin
            fsm_state <= FSM_IDLE;
            is_writing <= 0;
            nibbles_remaining <= 0;
            data_ready <= 0;
            spi_clk_out <= 0;
            spi_data_oe <= 4'b0000;
            spi_flash_select <= 1;
            spi_ram_a_select <= 1;
            spi_ram_b_select <= 1;
            data_req <= 0;
        end else begin
            data_ready <= 0;
            data_req <= 0;
            if (fsm_state == FSM_IDLE) begin
                if ((start_read || start_write) && !ram_a_block && !ram_b_block) begin
                    fsm_state <= addr_in[24] ? FSM_CMD : FSM_ADDR;
                    is_writing <= !start_read && addr_in[24];  // Only writes to RAM supported.
                    nibbles_remaining <= addr_in[24] ? 2-1 : 6-1;
                    spi_data_oe <= 4'b1111;
                    spi_clk_out <= 0;
                    spi_flash_select <= addr_in[24];
                    spi_ram_a_select <= addr_in[24:23] != 2'b10;
                    spi_ram_b_select <= addr_in[24:23] != 2'b11;
                end
            end else begin
                if (read_cycles_count == 0) read_cycles_count <= 3'b001;
                else read_cycles_count <= read_cycles_count - 3'b001;

                if (fsm_state == FSM_STALLED) begin
                    spi_clk_out <= 0;
                    if (!stall_txn && read_cycles_count < 3'b010) begin
                        data_ready <= !is_writing;
                        if (is_writing) begin
                            fsm_state <= FSM_DATA;
                            read_cycles_count <= 3'b000;
                        end else begin
                            fsm_state <= (delay_cycles_cfg[2:1] == 2'b00) ? FSM_DATA : FSM_STALL_RECOVER;
                            read_cycles_count <= {1'b0, delay_cycles_cfg[2], delay_cycles_cfg[0]};
                        end
                    end
                end else begin
                    spi_clk_out <= !spi_clk_out;
                    if (((fsm_state == FSM_DATA && !is_writing) || fsm_state == FSM_STALL_RECOVER) ? (read_cycles_count == 0) : spi_clk_out) begin
                        if (nibbles_remaining == 0 || (fsm_state == FSM_STALL_RECOVER && delay_cycles_cfg[2])) begin
                            if (fsm_state == FSM_DATA || fsm_state == FSM_STALL_RECOVER) begin
                                data_ready <= !is_writing && !stall_txn;
                                nibbles_remaining <= (DATA_WIDTH_BITS >> 2)-1;
                                if (stall_txn) begin
                                    fsm_state <= FSM_STALLED;
                                    read_cycles_count <= delay_cycles_cfg | 3'b001;
                                end else begin
                                    fsm_state <= FSM_DATA;
                                end
                            end else begin
                                fsm_state <= fsm_state + 1;
                                if (fsm_state == FSM_CMD) begin
                                    nibbles_remaining <= (ADDR_BITS >> 2)-1;
                                end
                                else if (fsm_state == FSM_ADDR) begin
                                    if (is_writing) begin
                                        fsm_state <= FSM_DATA;
                                        nibbles_remaining <= (DATA_WIDTH_BITS >> 2)-1;
                                    end else if (spi_flash_select) begin
                                        // On RAM, skip DUMMY1.
                                        fsm_state <= FSM_DUMMY2;
                                        spi_data_oe <= 4'b0000;
                                        nibbles_remaining <= 4-1;
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
                                    read_cycles_count <= delay_cycles_cfg;
                                end
                            end
                        end else begin
                            if (fsm_state == FSM_STALL_RECOVER) fsm_state <= FSM_DATA;
                            nibbles_remaining <= nibbles_remaining - 1;
                        end
                    end else begin
                        data_req <= is_writing && (fsm_state == FSM_DATA) && nibbles_remaining == 0;
                    end
                end
            end
        end
    end

/* verilator lint_on WIDTH */

    always @(posedge clk) begin
        if (fsm_state == FSM_IDLE && (start_read || start_write)) begin
            addr <= addr_in[23:0];
        end else if (fsm_state == FSM_ADDR && spi_clk_out) begin
            addr <= {addr[ADDR_BITS-5:0], 4'b0000};
        end
    end

    always @(posedge clk) begin
        if (is_writing) begin
            if (fsm_state == FSM_STALLED) begin
                data <= data_in;
            end else if (spi_clk_out) begin
                if (nibbles_remaining == 0) begin
                    data <= data_in;
                end else if (fsm_state == FSM_DATA) begin
                    data <= {data[DATA_WIDTH_BITS-5:0], spi_data_in};
                end
            end
        end else if (read_cycles_count == 0 && fsm_state == FSM_DATA) begin
            data <= {data[DATA_WIDTH_BITS-5:0], spi_data_in};
        end else if (read_cycles_count == 3'b010 && fsm_state == FSM_STALL_RECOVER) begin
            data <= {data[DATA_WIDTH_BITS-5:0], spi_in_buffer[7:4]};
        end else if (read_cycles_count == 0 && fsm_state == FSM_STALL_RECOVER) begin
            data <= {data[DATA_WIDTH_BITS-5:0], spi_in_buffer[3:0]};
        end else if (read_cycles_count[2:1] != 2'b00 && read_cycles_count[0] == 1'b0 && fsm_state == FSM_STALLED) begin
            spi_in_buffer <= {spi_in_buffer[3:0], spi_data_in};
        end
    end

    always @(*) begin
        case (fsm_state)
            FSM_CMD: begin // CMD only used for the PSRAM, the flash is always in continuous read mode
                if (is_writing) begin
                    // RAM Write command is 02h
                    if (nibbles_remaining[0])
                        spi_data_out = 4'b0000;
                    else
                        spi_data_out = 4'b0010;
                end else begin
                    // RAM Read command is 0Bh
                    if (nibbles_remaining[0])
                        spi_data_out = 4'b0000;
                    else
                        spi_data_out = 4'b1011;
                end
            end
            FSM_ADDR:   spi_data_out = addr[ADDR_BITS-1:ADDR_BITS-4];
            FSM_DUMMY1: spi_data_out = 4'b1010;
            FSM_DATA:   spi_data_out = data[DATA_WIDTH_BITS-1:DATA_WIDTH_BITS-4];
            default:    spi_data_out = 4'b1010;
        endcase
    end

    // Allow 2 cycles before reselecting the same RAM
    always @(posedge clk) begin
        if (!rstn) begin
            last_ram_a_sel <= 1;
            last_ram_b_sel <= 1;
        end else begin
            last_ram_a_sel <= spi_ram_a_select;
            last_ram_b_sel <= spi_ram_b_select;
        end
    end


    `ifdef FORMAL
    // register for knowing if we have just started
    reg [1:0] f_past_valid = 2'b00;
    reg f_reset_done = 0;
    wire f_any_select = spi_flash_select & spi_ram_a_select & spi_ram_b_select;
    // start in reset
    initial assume(!rstn);
    initial assume(spi_flash_select);
    initial assume(spi_ram_a_select);
    initial assume(spi_ram_b_select);
    always @(posedge clk) begin
        // update past_valid reg so we know it's safe to use $past()
        f_past_valid <= {f_past_valid[0], 1'b1};

        // Reset for 2 cycles, and then never again
        assume(((f_past_valid == 2'b11) ? 0 : 1) + rstn == 1);

        // Only select one chip
        if (f_past_valid)
            assert(spi_flash_select + spi_ram_a_select + spi_ram_b_select >= 2);

        // Busy is correct
        if (f_past_valid)
            if (spi_flash_select + spi_ram_a_select + spi_ram_b_select == 2)
                assert(busy);
            else
                assert(!busy);

        // RAM must be deselected for at least 2 cycles
        if (f_past_valid == 2'b11) begin
            assert(!(!spi_ram_a_select && $past(spi_ram_a_select) && $past(!spi_ram_a_select, 2)));
            assert(!(!spi_ram_b_select && $past(spi_ram_b_select) && $past(!spi_ram_b_select, 2)));
        end

        // Starting works
        assume(start_read + start_write < 2);
        if (start_write) assume(addr_in[24]);
        if (f_past_valid && $past(rstn && !busy && (start_read || start_write) && !stop_txn)) begin
            if (($past(addr_in[24:23] == 2'b10) && $past(!spi_ram_a_select, 2)) ||
                ($past(addr_in[24:23] == 2'b11) && $past(!spi_ram_b_select, 2))) begin
                assert(!busy);
            end else begin
                assert(busy);
                assert(is_writing == $past(start_write));
            end
        end

        // Only stall on request
        if (f_past_valid && fsm_state == FSM_STALLED && $past(fsm_state != FSM_STALLED))
            assert($past(stall_txn));

        // No positive clock edges when stalled
        if (f_past_valid == 2'b11 && $past(fsm_state == FSM_STALLED) && busy && $past(!spi_clk_out))
            assert(!spi_clk_out);

        // SPI Clock runs while transaction in progress and not stalled
        if (f_past_valid == 2'b11 && busy && fsm_state != FSM_STALLED && $past(fsm_state != FSM_IDLE && fsm_state != FSM_STALLED))
            assert(spi_clk_out != $past(spi_clk_out));

        // Data doesn't change over rising edge of clock
        if (f_past_valid && $past(busy) && busy && $past(!spi_clk_out) && spi_clk_out && ($past(spi_data_oe) || spi_data_oe))
            assert(spi_data_out == $past(spi_data_out));

        // Stopping works
        if (f_past_valid && $past(stop_txn && !is_writing)) begin
            assert(spi_flash_select + spi_ram_a_select + spi_ram_b_select == 3);
            assert(spi_clk_out == 0);
        end
        if (f_past_valid && $past(stop_txn && is_writing && spi_clk_out)) begin
            assert(spi_flash_select + spi_ram_a_select + spi_ram_b_select == 3);
            assert(spi_clk_out == 0);
        end

        if (!f_any_select) begin
            // Address can't change while selected
            assume(addr_in == $past(addr_in));

            // Data can only change when requested
            if (!data_req) assume(data_in == $past(data_in));

            // Data in can only change the correct number of cycles after a falling edge of clock
            assume(delay_cycles_cfg <= 5);
            if ((delay_cycles_cfg == 0 && !($past(spi_clk_out) && !spi_clk_out)) ||
                (delay_cycles_cfg == 1 && !($past(spi_clk_out, 2) && !$past(spi_clk_out))) ||
                (delay_cycles_cfg == 2 && !($past(spi_clk_out, 3) && !$past(spi_clk_out, 2))) ||
                (delay_cycles_cfg == 3 && !($past(spi_clk_out, 4) && !$past(spi_clk_out, 3))) ||
                (delay_cycles_cfg == 4 && !($past(spi_clk_out, 5) && !$past(spi_clk_out, 4))) ||
                (delay_cycles_cfg == 5 && !($past(spi_clk_out, 6) && !$past(spi_clk_out, 5))))
                    assume($past(spi_data_in) == $past(spi_data_in, 2));
            //else
            //    assume($past(spi_data_in) == $past(spi_data_in, 2) + 4'b0001);
        end
    end

    reg [5:0] f_counter = 0;
    reg [3:0] f_rcv_data [0:31];
    reg [5:0] f_rcv_index;
    wire [5:0] f_address_offset = spi_flash_select ? 2 : 0;
    reg f_ever_stalled = 0;
    always @(posedge clk) begin
        if (f_any_select) begin
            f_counter <= 0;
            f_rcv_index <= 12;
        end else if ($past(!spi_clk_out) && spi_clk_out) begin
            f_counter <= f_counter + 1;
            
            if (f_counter < 8 || is_writing) assert(spi_data_oe == 4'hF);
            else assert(spi_data_oe == 4'h0);

            // Verify command
            if (spi_flash_select) begin
                if (is_writing) begin
                    if (f_counter == 0) assert(spi_data_out == 4'h0);
                    if (f_counter == 1) assert(spi_data_out == 4'h2);
                end else begin
                    if (f_counter == 0) assert(spi_data_out == 4'h0);
                    if (f_counter == 1) assert(spi_data_out == 4'hB);
                end
            end

            // Verify address
            if (f_counter - f_address_offset == 0) assert(spi_data_out == addr_in[23:20]);
            if (f_counter - f_address_offset == 1) assert(spi_data_out == addr_in[19:16]);
            if (f_counter - f_address_offset == 2) assert(spi_data_out == addr_in[15:12]);
            if (f_counter - f_address_offset == 3) assert(spi_data_out == addr_in[11: 8]);
            if (f_counter - f_address_offset == 4) assert(spi_data_out == addr_in[ 7: 4]);
            if (f_counter - f_address_offset == 5) assert(spi_data_out == addr_in[ 3: 0]);

            if (f_counter > f_address_offset && f_counter - f_address_offset >= 6) begin
                if (is_writing) begin
                    // Verify written data
                    if (f_counter[0]) assert(spi_data_out == $past(data_in[3:0]));
                    else assert(spi_data_out == data_in[7:4]);
                end else begin
                    // Verify continuation mode
                    if (f_counter < 8) assert(spi_data_out == 4'hA);
                end
            end
        end

        // Record data
        if (delay_cycles_cfg == 0) f_rcv_data[f_counter] <= $past(spi_data_in);
        else if (delay_cycles_cfg == 1) f_rcv_data[$past(f_counter, 1)] <= $past(spi_data_in);
        else if (delay_cycles_cfg == 2) f_rcv_data[$past(f_counter, 2)] <= $past(spi_data_in);
        else if (delay_cycles_cfg == 3) f_rcv_data[$past(f_counter, 3)] <= $past(spi_data_in);
        else if (delay_cycles_cfg == 4) f_rcv_data[$past(f_counter, 4)] <= $past(spi_data_in);
        else if (delay_cycles_cfg == 5) f_rcv_data[$past(f_counter, 5)] <= $past(spi_data_in);

        if (f_past_valid && data_ready) begin
            assert(data_out[7:4] == f_rcv_data[f_rcv_index]);
            assert(data_out[3:0] == f_rcv_data[f_rcv_index+1]);
            f_rcv_index <= f_rcv_index + 2;
        end

        // Stall testing
        /*
        if (f_past_valid && f_rcv_index > 16 && stall_txn && $past(stall_txn) && $past(stall_txn, 2) && $past(stall_txn, 3) && $past(data_ready, 6))
            f_ever_stalled <= 1;

        cover(f_past_valid && f_ever_stalled && data_ready && $past(data_ready, 4) && f_rcv_index > 20);
        */
    end
    `endif

endmodule
