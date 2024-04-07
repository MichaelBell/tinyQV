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

    input [24:0] data_addr,
    input [1:0]  data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [1:0]  data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [31:0] data_to_write,

    input        data_continue, // Whether another read/write at the next address will immediately follow this one

    output         data_ready,  // Transaction complete/data request can be modified.
    output  [31:0] data_from_read,

    // External SPI interface
    input      [3:0] spi_data_in,
    output     [3:0] spi_data_out,
    output     [3:0] spi_data_oe,
    output           spi_clk_out,
    output           spi_flash_select,
    output           spi_ram_a_select,
    output           spi_ram_b_select,

    output        debug_stall_txn,
    output        debug_stop_txn
);

    // Combinational
    reg start_instr;
    reg start_read;
    reg start_write;
    reg stop_txn;
    reg [1:0] data_txn_n;
    reg [1:0] data_txn_len;

    reg qspi_write_done;
    wire qspi_busy;
    reg instr_active;

    wire is_instr = instr_active || start_instr;
    wire [1:0] txn_len = is_instr ? 2'b01 : data_txn_len;
    wire [24:0] addr_in = is_instr ? {1'b0, instr_addr, 1'b0} : data_addr[24:0];
    reg [31:0] qspi_data_buf;
    reg [1:0] qspi_data_byte_idx;
    wire qspi_data_req;
    wire qspi_data_ready;
    wire [7:0] qspi_data_out;

    // Only stall on the last byte of an instruction
    wire stall_txn = instr_active && instr_fetch_stall && !instr_ready && qspi_data_byte_idx == 2'b01;
    reg data_stall;

    always @(*) begin
        start_instr = 0;
        start_read = 0;
        start_write = 0;
        stop_txn = 0;
        data_txn_n = data_write_n & data_read_n;
        data_txn_len = {data_txn_n[1], data_txn_n[1] | data_txn_n[0]};  // 0, 1 or 3 for 1, 2 or 4 byte txn

        if (qspi_busy || qspi_write_done) begin
            // A transaction is running
            if (instr_active) begin
                if (instr_fetch_restart && (!instr_fetch_started || stall_txn)) begin
                    // Stop immediately on restart or if already stalled
                    stop_txn = 1;
                end else if ((qspi_data_ready && qspi_data_byte_idx == 2'b01) || instr_fetch_stall) begin
                    // End of previous transaction or instruction buffer full, stop if a data txn is waiting
                    if (data_txn_n != 2'b11) begin
                        stop_txn = 1;
                    end
                end
            end else if ((qspi_data_ready || qspi_data_req) && qspi_data_byte_idx == data_txn_len && !data_continue) begin
                // Data transaction is complete
                stop_txn = 1;
            end
        end else begin
            // No transaction, start one
            if (data_read_n != 2'b11)
                start_read = 1;
            else if (data_write_n != 2'b11)
                start_write = 1;
            else if (instr_fetch_restart)
                start_instr = 1;
        end
    end

    // State
    always @(posedge clk) begin
        if (!rstn || stop_txn) begin
            instr_active <= 0;
        end else begin
            instr_active <= qspi_busy ? instr_active : start_instr;
        end
    end

    wire [1:0] write_qspi_data_byte_idx = qspi_data_byte_idx + (qspi_data_req ? 2'b01 : 2'b00);
    qspi_controller q_ctrl(
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
        data_to_write[{write_qspi_data_byte_idx,3'b000} +:8],
        start_read || start_instr,
        start_write,
        stall_txn || data_stall,
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
            instr_fetch_started <= start_instr;
            instr_fetch_stopped <= stop_txn;
        end
    end

    always @(posedge clk) begin
        if (!rstn || start_instr || start_read || start_write) begin
            qspi_data_byte_idx <= 2'b00;
        end else begin
            if (qspi_data_ready || qspi_data_req) begin
                qspi_data_byte_idx <= qspi_data_byte_idx + 2'b01;

                if (qspi_data_byte_idx == txn_len) begin
                    qspi_data_byte_idx <= 0;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (qspi_data_ready) begin
            qspi_data_buf[{qspi_data_byte_idx,3'b000} +:8] <= qspi_data_out;
        end
    end

    assign instr_data = {qspi_data_out, qspi_data_buf[7:0]};
    assign instr_ready = instr_active && qspi_data_ready && qspi_data_byte_idx == 2'b01;

    always @(posedge clk) begin
        qspi_write_done <= qspi_data_req && qspi_data_byte_idx == data_txn_len;
    end

    always @(posedge clk) begin
        if (data_continue) begin
            if ((qspi_data_req && qspi_data_byte_idx + 2'b01 == data_txn_len) ||
                (qspi_data_ready && qspi_data_byte_idx == data_txn_len))
                data_stall <= 1;
            else if ((data_read_n != 2'b11 || data_write_n != 2'b11) && qspi_data_byte_idx == 2'b00 && !data_ready)
                data_stall <= 0;
        end else
            data_stall <= 0;
    end

    assign data_ready = !instr_active && ((qspi_data_ready && qspi_data_byte_idx == data_txn_len) || qspi_write_done);
    assign data_from_read = data_ready ? ({qspi_data_out, qspi_data_buf[23:16],
        data_txn_len == 2'b01 ? qspi_data_out : qspi_data_buf[15:8],
        data_txn_len == 2'b00 ? qspi_data_out : qspi_data_buf[7:0]}) : qspi_data_buf;

    assign debug_stall_txn = stall_txn;
    assign debug_stop_txn = stop_txn;

endmodule
