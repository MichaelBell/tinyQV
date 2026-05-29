/* TinyQV: A RISC-V core designed to use minimal area.
  
   This module wraps an SRAM primitive to provide scratch RAM.

   This version wraps the gf180 primitive.
 */

`default_nettype none

`ifndef NO_SCRATCH
module tinyqv_scratch #(parameter ADDR_BITS=9) (
    input         clk,
    input         rstn,

    input [ADDR_BITS-1:0] data_addr,
    input [1:0]   data_write_n,
    input [2:0]   counter,

    input [3:0]   data_in,
    output [3:0]  data_out
);

    wire write_enable_n;
    wire [7:0] write_bit_enable_n;
    wire [7:0] data_from_read;
    wire [1:0] byte_in_word;

    /* verilator lint_off PINMISSING */
    gf180mcu_ocd_ip_sram__sram512x8m8wm1 i_sram (
        .CLK(clk),
        .CEN(!rstn),
        .GWEN(write_enable_n),
        .WEN(write_bit_enable_n),
        .A({data_addr[ADDR_BITS-1:2], byte_in_word}),
        .D({data_in, data_in}),
        .Q(data_from_read)
    );
    /* verilator lint_on PINMISSING */

    assign data_out = counter[0] ? data_from_read[7:4] : data_from_read[3:0];

    assign write_enable_n = 
        !((data_write_n == 2'b00 && counter[2:1] == 2'b00) ||
          (data_write_n == 2'b01 && !counter[2]) ||
          (data_write_n == 2'b10));

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
