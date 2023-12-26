/* A RISC-V core designed to use minimal area.
  
   Aim is to support RV32E 
 */

module tb_qspi_flash (
    input clk,
    input rstn,

    // External SPI interface
    input      [3:0] spi_data_in,
    output     [3:0] spi_data_out,
    output     [3:0] spi_data_oe,
    output           spi_select,
    output           spi_clk_out,

    // Internal interface for reading/writing data
    input [23:0]  addr_in,
    input         start_read,
    input         stall_read,
    input         stop_read,

    output [15:0] data_out,
    output        data_ready,
    output        busy
);

`ifdef COCOTB_SIM
initial begin
  $dumpfile ("qspi_flash.vcd");
  $dumpvars (0, tb_qspi_flash);
  #1;
end
`endif

    qspi_flash_controller i_flash(
        clk,
        rstn,

        spi_data_in,
        spi_data_out,
        spi_data_oe,
        spi_select,
        spi_clk_out,

        addr_in,
        start_read,
        stall_read,
        stop_read,

        data_out,
        data_ready,
        busy
    );

endmodule