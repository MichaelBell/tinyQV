/* TinyQV: A RISC-V core designed to use minimal area.
  
   This module wraps an SRAM primitive to provide scratch RAM.

   This version wraps the gf180 primitive.
 */

`default_nettype none

`ifndef NO_SCRATCH
module tinyqv_scratch #(parameter ADDR_BITS=14) (
    input         clk,
    input         rstn,

    input [ADDR_BITS-1:0] data_addr,
    input [1:0]   data_write_n,
    input [2:0]   counter,

    input [3:0]   data_in,
    output [3:0]  data_out
);

    wire write_enable_n;
    wire write_enable1_n;
    wire write_enable2_n;
    wire [7:0] write_enable0_n;
    wire [7:0] write_bit_enable_n;
    reg [7:0] data_from_read;
    wire [7:0] data_from_read1;
    wire [7:0] data_from_read2;
    wire [7:0] data_from_read0 [0:7];
    wire [1:0] byte_in_word;

    /* verilator lint_off PINMISSING */
    gf180mcu_ocd_ip_sram__sram512x8m8wm1 i_sram1 (
        .CLK(clk),
        .CEN(!rstn),
        .GWEN(write_enable1_n),
        .WEN(write_bit_enable_n),
        .A({data_addr[8:2], byte_in_word}),
        .D({data_in, data_in}),
        .Q(data_from_read1)
    );
    gf180mcu_ocd_ip_sram__sram1024x8m8wm1 i_sram2 (
        .CLK(clk),
        .CEN(!rstn),
        .GWEN(write_enable2_n),
        .WEN(write_bit_enable_n),
        .A({data_addr[9:2], byte_in_word}),
        .D({data_in, data_in}),
        .Q(data_from_read2)
    );

    gf180mcu_ocd_ip_sram__sram1024x8m8wm1 i_sram00 (
        .CLK(clk),
        .CEN(!rstn),
        .GWEN(write_enable0_n[0]),
        .WEN(write_bit_enable_n),
        .A({data_addr[9:2], byte_in_word}),
        .D({data_in, data_in}),
        .Q(data_from_read0[0])
    );
    gf180mcu_ocd_ip_sram__sram1024x8m8wm1 i_sram01 (
        .CLK(clk),
        .CEN(!rstn),
        .GWEN(write_enable0_n[1]),
        .WEN(write_bit_enable_n),
        .A({data_addr[9:2], byte_in_word}),
        .D({data_in, data_in}),
        .Q(data_from_read0[1])
    );
    gf180mcu_ocd_ip_sram__sram1024x8m8wm1 i_sram02 (
        .CLK(clk),
        .CEN(!rstn),
        .GWEN(write_enable0_n[2]),
        .WEN(write_bit_enable_n),
        .A({data_addr[9:2], byte_in_word}),
        .D({data_in, data_in}),
        .Q(data_from_read0[2])
    );
    gf180mcu_ocd_ip_sram__sram1024x8m8wm1 i_sram03 (
        .CLK(clk),
        .CEN(!rstn),
        .GWEN(write_enable0_n[3]),
        .WEN(write_bit_enable_n),
        .A({data_addr[9:2], byte_in_word}),
        .D({data_in, data_in}),
        .Q(data_from_read0[3])
    );
    gf180mcu_ocd_ip_sram__sram1024x8m8wm1 i_sram04 (
        .CLK(clk),
        .CEN(!rstn),
        .GWEN(write_enable0_n[4]),
        .WEN(write_bit_enable_n),
        .A({data_addr[9:2], byte_in_word}),
        .D({data_in, data_in}),
        .Q(data_from_read0[4])
    );
    gf180mcu_ocd_ip_sram__sram1024x8m8wm1 i_sram05 (
        .CLK(clk),
        .CEN(!rstn),
        .GWEN(write_enable0_n[5]),
        .WEN(write_bit_enable_n),
        .A({data_addr[9:2], byte_in_word}),
        .D({data_in, data_in}),
        .Q(data_from_read0[5])
    );
    gf180mcu_ocd_ip_sram__sram1024x8m8wm1 i_sram06 (
        .CLK(clk),
        .CEN(!rstn),
        .GWEN(write_enable0_n[6]),
        .WEN(write_bit_enable_n),
        .A({data_addr[9:2], byte_in_word}),
        .D({data_in, data_in}),
        .Q(data_from_read0[6])
    );
    gf180mcu_ocd_ip_sram__sram1024x8m8wm1 i_sram07 (
        .CLK(clk),
        .CEN(!rstn),
        .GWEN(write_enable0_n[7]),
        .WEN(write_bit_enable_n),
        .A({data_addr[9:2], byte_in_word}),
        .D({data_in, data_in}),
        .Q(data_from_read0[7])
    );
    /* verilator lint_on PINMISSING */

    always @(*) begin
        case (data_addr[13:10])
            4'b0110: data_from_read = data_from_read0[0];
            4'b0111: data_from_read = data_from_read0[1];
            4'b1000: data_from_read = data_from_read0[2];
            4'b1001: data_from_read = data_from_read0[3];
            4'b1010: data_from_read = data_from_read0[4];
            4'b1011: data_from_read = data_from_read0[5];
            4'b1100: data_from_read = data_from_read0[6];
            4'b1101: data_from_read = data_from_read0[7];
            4'b1110: data_from_read = data_from_read2;
            4'b1111: data_from_read = data_from_read1;
            default: data_from_read = 0;
        endcase
    end
    assign data_out = counter[0] ? data_from_read[7:4] : data_from_read[3:0];

    assign write_enable_n = 
        !((data_write_n == 2'b00 && counter[2:1] == 2'b00) ||
          (data_write_n == 2'b01 && !counter[2]) ||
          (data_write_n == 2'b10));
    
    assign write_enable1_n = write_enable_n || data_addr[13:10] != 4'b1111;
    assign write_enable2_n = write_enable_n || data_addr[13:10] != 4'b1110;
    assign write_enable0_n[0] = write_enable_n || data_addr[13:10] != 4'b0110;
    assign write_enable0_n[1] = write_enable_n || data_addr[13:10] != 4'b0111;
    assign write_enable0_n[2] = write_enable_n || data_addr[13:10] != 4'b1000;
    assign write_enable0_n[3] = write_enable_n || data_addr[13:10] != 4'b1001;
    assign write_enable0_n[4] = write_enable_n || data_addr[13:10] != 4'b1010;
    assign write_enable0_n[5] = write_enable_n || data_addr[13:10] != 4'b1011;
    assign write_enable0_n[6] = write_enable_n || data_addr[13:10] != 4'b1100;
    assign write_enable0_n[7] = write_enable_n || data_addr[13:10] != 4'b1101;

    assign write_bit_enable_n = {{4{!counter[0]}}, {4{counter[0]}}};

    // Byte address:
    // - For writes this should be the data address + the counter/2 (as the counter counts in nibbles)
    // - For reads this needs to give the correct address to read the nibble on the next cycle.
    //   Therefore, increment by 1 on the second half of each byte.
    //   Note the first byte is read on the last count of the previous cycle (this is OK because the 
    //   address is already complete by then).
    // Can use OR instead of ADD because we assume the address is aligned for the width of the transaction.
    assign byte_in_word = (counter[2:1] + {1'b0, counter[0] && (data_write_n == 2'b11)}) | data_addr[1:0];

endmodule
`endif
