/* TinyQV: A RISC-V core designed to use minimal area.
  
   This memory controller plumbs the outputs from the CPU into the Flash and RAM controllers
 */

module tinyqv_mem_ctrl (
    input clk,
    input rstn,

    input [23:1] instr_addr,
    input        instr_fetch_restart,
    input        instr_fetch_stall,

    output reg     instr_fetch_started,
    output reg     instr_fetch_stopped,
    output  [15:0] instr_data,
    output         instr_ready,

    input [27:0] data_addr,
    input [1:0]  data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [1:0]  data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [31:0] data_to_write,

    output         data_ready,  // Transaction complete/data request can be modified.
    output  [31:0] data_from_read,

    // External SPI interface
    input      [3:0] spi_data_in,
    output     [3:0] spi_data_out,
    output reg [3:0] spi_data_oe,
    output           spi_select_flash,
    output           spi_select_ram_a,
    output           spi_select_ram_b,
    output reg       spi_clk_out
);

    wire flash_data_sel = 1'b0; //data_addr[27:24] == 4'h0 && data_read_n != 2'b11;
    wire [23:0] flash_addr_in = flash_data_sel ? data_addr[23:0] : {instr_addr, 1'b0};
    wire flash_busy;
    wire [15:0] flash_data_out;
    wire flash_data_ready;

    reg flash_stop_read;
    always @(posedge clk) begin
        if (!rstn) flash_stop_read <= 1'b0;
        else flash_stop_read <= flash_busy && instr_fetch_restart;
    end
        
    wire flash_start_read = instr_fetch_restart && !flash_stop_read && !flash_busy;  // TODO
    wire flash_stall_read = flash_data_sel ? 1'b0 : instr_fetch_stall;


    qspi_flash_controller i_flash(
        clk,
        rstn,

        spi_data_in,
        spi_data_out,
        spi_data_oe,
        spi_select_flash,
        spi_clk_out,

        flash_addr_in,
        flash_start_read,
        flash_stall_read,
        flash_stop_read,

        flash_data_out,
        flash_data_ready,
        flash_busy
    );

    always @(posedge clk) begin
        if (!rstn) begin
            instr_fetch_started <= 1'b0;
            instr_fetch_stopped <= 1'b0;
        end else begin
            instr_fetch_started <= flash_start_read;
            instr_fetch_stopped <= flash_stop_read;
        end
    end

    assign instr_data = flash_data_out;
    assign instr_ready = flash_data_ready;

    assign data_ready = 1'b0;
    assign data_from_read = 32'd0;

    assign spi_select_ram_a = 1'b1;
    assign spi_select_ram_b = 1'b1;

endmodule
