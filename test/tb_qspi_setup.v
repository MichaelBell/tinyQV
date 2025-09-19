/* A RISC-V core designed to use minimal area.
  
   Aim is to support RV32E 
 */

module tb_qspi_setup (
    input clk,
    input rstn,

    // External SPI interface
    output [3:0] spi_data_out,
    output [3:0] spi_data_oe,
    output       spi_clk_out,

    output       spi_flash_select,
    output       spi_ram_a_select,
    output       spi_ram_b_select,

    output       done
);

`ifdef COCOTB_SIM
initial begin
  $dumpfile ("qspi_setup.vcd");
  $dumpvars (0, tb_qspi_setup);
  #1;
end
`endif

    qspi_setup i_flash(
        clk,
        rstn,

        spi_data_out,
        spi_data_oe,
        spi_clk_out,

        spi_flash_select,
        spi_ram_a_select,
        spi_ram_b_select,

        done
    );

endmodule