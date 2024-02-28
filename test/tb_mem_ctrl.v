/* A RISC-V core designed to use minimal area.
  
   Aim is to support RV32E 
 */

module tb_mem_ctrl (
    input clk,
    input rstn,

    input [23:1] instr_addr,
    input        instr_fetch_restart,
    input        instr_fetch_stall,

    output         instr_fetch_started,
    output         instr_fetch_stopped,
    output  [15:0] instr_data,
    output         instr_ready,

    input [24:0] data_addr,
    input [1:0]  data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [1:0]  data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [31:0] data_to_write,

    input        data_continue,

    output         data_ready,  // Transaction complete/data request can be modified.
    output  [31:0] data_from_read,

    // External SPI interface
    input      [3:0] spi_data_in,
    output     [3:0] spi_data_out,
    output     [3:0] spi_data_oe,
    output           spi_flash_select,
    output           spi_ram_a_select,
    output           spi_ram_b_select,
    output           spi_clk_out
);

`ifdef COCOTB_SIM
initial begin
  $dumpfile ("mem_ctrl.vcd");
  $dumpvars (0, tb_mem_ctrl);
  #1;
end
`endif

    tinyqv_mem_ctrl i_memctrl(
        .clk(clk),
        .rstn(rstn),

        .instr_addr(instr_addr),
        .instr_fetch_restart(instr_fetch_restart),
        .instr_fetch_stall(instr_fetch_stall),

        .instr_fetch_started(instr_fetch_started),
        .instr_fetch_stopped(instr_fetch_stopped),
        .instr_data(instr_data),
        .instr_ready(instr_ready),

        .data_addr(data_addr),
        .data_write_n(data_write_n),
        .data_read_n(data_read_n),
        .data_to_write(data_to_write),

        .data_continue(data_continue),

        .data_ready(data_ready),
        .data_from_read(data_from_read),

        .spi_data_in(spi_data_in),
        .spi_data_out(spi_data_out),
        .spi_data_oe(spi_data_oe),
        .spi_flash_select(spi_flash_select),
        .spi_ram_a_select(spi_ram_a_select),
        .spi_ram_b_select(spi_ram_b_select),
        .spi_clk_out(spi_clk_out)
    );

endmodule