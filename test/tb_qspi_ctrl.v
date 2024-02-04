/* A RISC-V core designed to use minimal area.
  
   Aim is to support RV32E 
 */

module tb_qspi_ctrl (
    input clk,
    input rstn,

    // External SPI interface
    input      [3:0] spi_data_in,
    output     [3:0] spi_data_out,
    output     [3:0] spi_data_oe,
    output           spi_clk_out,

    output           spi_flash_select,
    output           spi_ram_a_select,
    output           spi_ram_b_select,

    // Internal interface for reading/writing data
    input [24:0] addr_in,
    input  [7:0] data_in,
    input        start_read,
    input        start_write,
    input        stall_txn,
    input        stop_txn,

    output [7:0] data_out,
    output       data_req,
    output       data_ready,
    output       busy
);

`ifdef COCOTB_SIM
initial begin
  $dumpfile ("qspi_ctrl.vcd");
  $dumpvars (0, tb_qspi_ctrl);
  #1;
end
`endif

    qspi_controller i_ctrl(
        clk,
        rstn,

        spi_data_in,
        spi_data_out,
        spi_data_oe,
        spi_clk_out,

        spi_flash_select,
        spi_ram_a_select,
        spi_ram_b_select,

        addr_in,
        data_in,
        start_read,
        start_write,
        stall_txn,
        stop_txn,

        data_out,
        data_req,
        data_ready,
        busy
    );

endmodule