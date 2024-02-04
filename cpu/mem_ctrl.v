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
    output           spi_flash_select,
    output           spi_ram_a_select,
    output           spi_ram_b_select,
    output reg       spi_clk_out
);

    wire [24:0] addr_in = {1'b0, instr_addr, 1'b0};
    wire qspi_busy;
    reg [23:0] qspi_data_buf;
    reg [1:0] qspi_data_byte_idx;
    wire qspi_data_req;
    wire qspi_data_ready;
    wire [7:0] qspi_data_out;

    reg stop_txn;
    always @(posedge clk) begin
        if (!rstn) stop_txn <= 1'b0;
        else stop_txn <= qspi_busy && instr_fetch_restart;
    end
        
    wire start_read = instr_fetch_restart && !stop_txn && !qspi_busy;  // TODO
    wire start_write = 1'b0;
    wire stall_txn = instr_fetch_stall;


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
        data_to_write[{qspi_data_byte_idx,3'b000} +:8],
        start_read,
        start_write,
        stall_txn,
        stop_txn,

        qspi_data_out,
        qspi_data_req,
        qspi_data_ready,
        qspi_busy
    );

    always @(posedge clk) begin
        if (!rstn) begin
            instr_fetch_started <= 1'b0;
            instr_fetch_stopped <= 1'b0;
        end else begin
            instr_fetch_started <= start_read;
            instr_fetch_stopped <= stop_txn;
        end
    end

    always @(posedge clk) begin
        if (!rstn || start_read || start_write) begin
            qspi_data_byte_idx <= 2'b00;
        end else begin
            if (qspi_data_ready || qspi_data_req) begin
                qspi_data_byte_idx <= qspi_data_byte_idx + 1;

                // TODO: Different transaction types/lengths
                if (qspi_data_byte_idx == 2-1) begin
                    qspi_data_byte_idx <= 0;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (qspi_data_ready && qspi_data_byte_idx != 2'b11) begin
            qspi_data_buf[{qspi_data_byte_idx,3'b000} +:8] <= qspi_data_out;
        end
    end

    assign instr_data = {qspi_data_out, qspi_data_buf[7:0]};
    assign instr_ready = qspi_data_ready && qspi_data_byte_idx == 2'b01;

    assign data_ready = 1'b0;
    assign data_from_read = {qspi_data_out, qspi_data_buf};

endmodule
