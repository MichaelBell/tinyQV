// Copyright (c) 2021 Ben Marshall
// Changes Copyright (c) 2023 Michael Bell
// MIT License

// 
// Module: uart_tx 
// 
// Notes:
// - UART transmitter module.
//

module uart_tx #(parameter 
    BIT_RATE     = 9600,       // Input bit rate of the UART line, bits / sec
    CLK_HZ       = 50_000_000, // Clock frequency in hertz.
    PAYLOAD_BITS = 8,          // Number of data bits sent per UART packet.
    STOP_BITS    = 1           // Number of stop bits indicating the end of a packet.
) (
    input  wire         clk         , // Top level system clock input.
    input  wire         resetn      , // Asynchronous active low reset.
    output wire         uart_txd    , // UART transmit pin.
    output wire         uart_tx_busy, // Module busy sending previous item.
    input  wire         uart_tx_en  , // Send the data on uart_tx_data
    input  wire [PAYLOAD_BITS-1:0]   uart_tx_data  // The data to be sent
);

// --------------------------------------------------------------------------- 
// Internal parameters.
// 

//
// Number of clock cycles per uart bit.
localparam       CYCLES_PER_BIT     = (CLK_HZ - 1) / BIT_RATE;

//
// Size of the registers which store sample counts and bit durations.
localparam       COUNT_REG_LEN      = 1+$clog2(CYCLES_PER_BIT);

// --------------------------------------------------------------------------- 
// Internal registers.
// 

//
// Internally latched value of the uart_txd line. Helps break long timing
// paths from the logic to the output pins.
reg txd_reg;

//
// Storage for the serial data to be sent.
reg [PAYLOAD_BITS-1:0] data_to_send;

//
// Counter for the number of cycles over a packet bit.
reg [COUNT_REG_LEN-1:0] cycle_counter;

//
// Current and next states of the internal FSM.
reg [3:0] fsm_state;

localparam FSM_IDLE = 0;
localparam FSM_START= 1;
localparam FSM_SEND = 2;
localparam FSM_STOP = 2 + PAYLOAD_BITS;
localparam FSM_END = FSM_STOP + STOP_BITS - 1;

// --------------------------------------------------------------------------- 
// FSM next state selection.
// 

assign uart_tx_busy = fsm_state != FSM_IDLE;
assign uart_txd     = txd_reg;

wire next_bit     = cycle_counter == CYCLES_PER_BIT[COUNT_REG_LEN-1:0];

//
// Handle picking the next state.
function [3:0] next_fsm_state(input tx_en);
    if (fsm_state == FSM_IDLE) begin
        if (tx_en) next_fsm_state = FSM_START;
        else next_fsm_state = FSM_IDLE;
    end else begin
        if (next_bit) begin
            if (fsm_state == FSM_END) next_fsm_state = FSM_IDLE;
            else next_fsm_state = fsm_state + 1;
        end else begin
            next_fsm_state = fsm_state;
        end
    end
endfunction

// --------------------------------------------------------------------------- 
// Internal register setting and re-setting.
// 

//
// Handle updates to the sent data register.
always @(posedge clk) begin : p_data_to_send
    if(!resetn) begin
        data_to_send <= {PAYLOAD_BITS{1'b0}};
    end else if(fsm_state == FSM_IDLE && uart_tx_en) begin
        data_to_send <= uart_tx_data;
    end else if(fsm_state >= FSM_SEND && fsm_state < FSM_STOP && next_bit) begin
        data_to_send <= {1'b0, data_to_send[PAYLOAD_BITS-1:1]};
    end
end


//
// Increments the cycle counter when sending.
always @(posedge clk) begin : p_cycle_counter
    if(!resetn) begin
        cycle_counter <= {COUNT_REG_LEN{1'b0}};
    end else if(next_bit) begin
        cycle_counter <= {COUNT_REG_LEN{1'b0}};
    end else if(fsm_state != FSM_IDLE) begin
        cycle_counter <= cycle_counter + 1'b1;
    end
end


//
// Progresses the next FSM state.
always @(posedge clk) begin : p_fsm_state
    if(!resetn) begin
        fsm_state <= FSM_IDLE;
    end else begin
        fsm_state <= next_fsm_state(uart_tx_en);
    end
end


//
// Responsible for updating the internal value of the txd_reg.
always @(posedge clk) begin : p_txd_reg
    if(!resetn) begin
        txd_reg <= 1'b1;
    end else if(fsm_state == FSM_START) begin
        txd_reg <= 1'b0;
    end else if(fsm_state >= FSM_SEND && fsm_state < FSM_STOP) begin
        txd_reg <= data_to_send[0];
    end else begin
        txd_reg <= 1'b1;
    end
end

endmodule
