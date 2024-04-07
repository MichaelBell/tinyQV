// Copyright (c) 2021 Ben Marshall
// Changes Copyright (c) 2023 Michael Bell
// MIT License

// 
// Module: uart_rx 
// 
// Notes:
// - UART reciever module.
//

module uart_rx #(parameter 
    BIT_RATE     = 9600,       // Input bit rate of the UART line, bits / sec
    CLK_HZ       = 50_000_000, // Clock frequency in hertz.
    PAYLOAD_BITS = 8,          // Number of data bits recieved per UART packet.
    STOP_BITS    = 1           // Number of stop bits indicating the end of a packet.
) (
    input  wire       clk          , // Top level system clock input.
    input  wire       resetn       , // Asynchronous active low reset.
    input  wire       uart_rxd     , // UART Recieve pin.
    output reg        uart_rts     , // UART Request to send pin.
    input  wire       uart_rx_read , // Available byte has been read and can be cleared.
    output wire       uart_rx_valid, // Valid data recieved and available.
    output wire [PAYLOAD_BITS-1:0] uart_rx_data   // The recieved data.
);

// -------------------------------------------------------------------------- 
// Internal parameters.
// 

//
// Number of clock cycles per uart bit.
localparam       CYCLES_PER_BIT     = (CLK_HZ - 1) / BIT_RATE;

//
// Size of the registers which store sample counts and bit durations.
localparam       COUNT_REG_LEN      = 1+$clog2(CYCLES_PER_BIT);

// -------------------------------------------------------------------------- 
// Internal registers.
// 

//
// Internally latched value of the uart_rxd line. Avoids metastable states.
reg [1:0] rxd_reg;

//
// Storage for the recieved serial data.
reg [PAYLOAD_BITS-1:0] recieved_data;

//
// Counter for the number of cycles over a packet bit.
reg [COUNT_REG_LEN-1:0] cycle_counter;

//
// Sample of the UART input line whenever we are in the middle of a bit frame.
reg bit_sample;

//
// Current and next states of the internal FSM.
reg [3:0] fsm_state;

localparam FSM_IDLE = 0;
localparam FSM_START= 1;
localparam FSM_RECV = 2;
localparam FSM_STOP = 2 + PAYLOAD_BITS;
localparam FSM_READY = FSM_STOP + STOP_BITS;

// --------------------------------------------------------------------------- 
// Output assignment
// 

assign uart_rx_valid = fsm_state == FSM_READY;
assign uart_rx_data = recieved_data;

// --------------------------------------------------------------------------- 
// FSM next state selection.
// 

wire next_bit     = cycle_counter == CYCLES_PER_BIT[COUNT_REG_LEN-1:0];
wire mid_bit      = cycle_counter == CYCLES_PER_BIT[COUNT_REG_LEN-1:0] / 2;

//
// Handle picking the next state.
function [3:0] next_fsm_state();
    case(fsm_state)
        FSM_IDLE : next_fsm_state = rxd_reg[0]  ? FSM_IDLE  : FSM_START;
        
        // Only go STOP -> READY on a valid STOP bit.
        FSM_STOP : next_fsm_state = mid_bit     ? (rxd_reg[0] ? FSM_READY : FSM_IDLE) : FSM_STOP;

        FSM_READY: next_fsm_state = uart_rx_read? FSM_IDLE  : FSM_READY;

        default  : next_fsm_state = next_bit    ? fsm_state + 1 : fsm_state;
    endcase
endfunction

// --------------------------------------------------------------------------- 
// Internal register setting and re-setting.
// 

//
// Handle updates to the recieved data register.
always @(posedge clk) begin : p_recieved_data
    if(!resetn) begin
        recieved_data <= {PAYLOAD_BITS{1'b0}};
    end else if(fsm_state == FSM_IDLE             ) begin
        recieved_data <= {PAYLOAD_BITS{1'b0}};
    end else if(fsm_state >= FSM_RECV && fsm_state < FSM_STOP && next_bit ) begin
        recieved_data <= {bit_sample, recieved_data[PAYLOAD_BITS-1:1]};
    end
end

//
// Sample the recieved bit when in the middle of a bit frame.
always @(posedge clk) begin : p_bit_sample
    if(!resetn) begin
        bit_sample <= 1'b0;
    end else if (mid_bit) begin
        bit_sample <= rxd_reg[0];
    end
end


//
// Increments the cycle counter when recieving.
always @(posedge clk) begin : p_cycle_counter
    if(!resetn) begin
        cycle_counter <= {COUNT_REG_LEN{1'b0}};
    end else if(next_bit || fsm_state == FSM_IDLE || fsm_state == FSM_READY) begin
        cycle_counter <= {COUNT_REG_LEN{1'b0}};
    end else begin
        cycle_counter <= cycle_counter + 1'b1;
    end
end


//
// Progresses the next FSM state.
always @(posedge clk) begin : p_fsm_state
    if(!resetn) begin
        fsm_state <= FSM_IDLE;
    end else begin
        fsm_state <= next_fsm_state();
    end
end

// Sets RTS
always @(posedge clk) begin : p_rts
    if (!resetn) begin
        uart_rts <= 1'b1;
    end else begin
        uart_rts <= fsm_state > FSM_START;  // RTS is active low, 0 when IDLE or START.
    end
end

//
// Responsible for updating the internal value of the rxd_reg.
always @(posedge clk) begin : p_rxd_reg
    if(!resetn) begin
        rxd_reg     <= 2'b11;
    end else begin
        rxd_reg     <= {uart_rxd, rxd_reg[1]};
    end
end


endmodule
