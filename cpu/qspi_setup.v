/* Copyright 2025 (c) Michael Bell
   SPDX-License-Identifier: Apache-2.0

   QSPI setup for TinyQV.  This puts the PSRAMs into QSPI mode and issues a flash 
   fast read quad I/O (EBh) command to start continuous read mode, as expected by
   the TinyQV QSPI controller.
*/

`default_nettype none

module qspi_setup (
    input clk,
    input rstn,

    // External SPI interface
    output reg [3:0] spi_data_out,
    output reg [3:0] spi_data_oe,
    output           spi_clk_out,

    output reg       spi_flash_select,
    output reg       spi_ram_a_select,
    output reg       spi_ram_b_select,

    output       done
);

    localparam FSM_FLASH_RESET = 3'd0;
    localparam FSM_FLASH_PAUSE = 3'd1;
    localparam FSM_FLASH_CMD   = 3'd2;
    localparam FSM_FLASH_ADDR  = 3'd3;
    localparam FSM_FLASH_READ  = 3'd4;
    localparam FSM_RAM_A_CMD   = 3'd5;
    localparam FSM_RAM_B_CMD   = 3'd6;
    localparam FSM_DONE        = 3'd7;

    reg [2:0] fsm_state;
    reg [3:0] counter;

    always @(posedge clk) begin
        if (!rstn) begin
            fsm_state <= 0;
            counter <= 0;
            spi_data_oe <= 4'b0000;
            spi_flash_select <= 1;
            spi_ram_a_select <= 1;
            spi_ram_b_select <= 1;            
        end else begin
            counter <= counter + 1;

            case (fsm_state)
            FSM_FLASH_RESET: begin
                if (spi_flash_select) begin
                    spi_flash_select <= 0;
                    counter <= 0;
                    spi_data_oe <= 4'b0001;
                    spi_data_out <= 4'b0001;
                end
                if (counter == 4'hf) begin
                    fsm_state <= FSM_FLASH_PAUSE;
                    spi_flash_select <= 1;
                end
            end
            FSM_FLASH_PAUSE: begin
                counter <= counter + 2;
                if (counter[2]) begin
                    spi_flash_select <= 0;
                    fsm_state <= FSM_FLASH_CMD;
                    counter <= 0;
                    spi_data_oe <= 4'b0001;
                    spi_data_out <= 4'b0001;
                end
            end
            FSM_FLASH_CMD: begin
                if (counter == 4'h5 || counter == 4'h9) begin
                    spi_data_out <= 4'b0000;
                end
                if (counter == 4'h7 || counter == 4'hb) begin
                    spi_data_out <= 4'b0001;
                end
                if (counter == 4'hf) begin
                    fsm_state <= FSM_FLASH_ADDR;
                    spi_data_oe <= 4'b1111;
                    spi_data_out <= 4'b0000;
                end
            end
            FSM_FLASH_ADDR: begin
                if (counter == 4'hb) begin
                    spi_data_out <= 4'b1010;
                end
                if (counter == 4'hf) begin
                    fsm_state <= FSM_FLASH_READ;
                    spi_data_oe <= 4'b0000;
                    spi_data_out <= 4'b0000;
                end
            end
            FSM_FLASH_READ: begin
                if (counter == 4'hf) begin
                    fsm_state <= FSM_RAM_A_CMD;
                    spi_flash_select <= 1;
                    spi_ram_a_select <= 0;
                    spi_data_oe <= 4'b0001;
                    spi_data_out <= 4'b0000;
                end
            end
            FSM_RAM_A_CMD: begin
                if (counter == 4'h3 || counter == 4'h9 || counter == 4'hd) begin
                    spi_data_out <= 4'b0001;
                end
                if (counter == 4'h7 || counter == 4'hb) begin
                    spi_data_out <= 4'b0000;
                end
                if (counter == 4'hf) begin
                    fsm_state <= FSM_RAM_B_CMD;
                    spi_ram_a_select <= 1;
                    spi_ram_b_select <= 0;
                    spi_data_out <= 4'b0000;
                end
            end
            FSM_RAM_B_CMD: begin
                if (counter == 4'h3 || counter == 4'h9 || counter == 4'hd) begin
                    spi_data_out <= 4'b0001;
                end
                if (counter == 4'h7 || counter == 4'hb) begin
                    spi_data_out <= 4'b0000;
                end
                if (counter == 4'hf) begin
                    fsm_state <= FSM_DONE;
                    spi_ram_b_select <= 1;
                    spi_data_oe <= 4'b0000;
                end
            end
            FSM_DONE: begin
                counter <= 0;
            end
            endcase
        end
    end

    assign done = fsm_state == FSM_DONE;
    assign spi_clk_out = counter[0];

endmodule
