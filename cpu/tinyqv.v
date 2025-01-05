/*
 * Copyright (c) 2024 Michael Bell
 * SPDX-License-Identifier: Apache-2.0
 */

`define default_netname none

// TinyQV CPU and QSPI memory controller wrapper
module tinyQV (
    input clk,
    input rstn,

    // Interface for non-memory transactions, implemented by external devices
    output [27:0] data_addr,
    output  [1:0] data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    output  [1:0] data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    output        data_read_complete,
    output [31:0] data_out,    

    input         data_ready,  // Transaction complete/data request can be modified.
    input  [31:0] data_in,

    // Interrupt requests: Bottom 2 bits trigger on rising edge, next two are a status
    input   [3:0] interrupt_req,

    // External SPI interface
    input   [3:0] spi_data_in,
    output  [3:0] spi_data_out,
    output  [3:0] spi_data_oe,
    output        spi_clk_out,

    output        spi_flash_select,
    output        spi_ram_a_select,
    output        spi_ram_b_select,

    output        debug_instr_complete,
    output        debug_instr_ready,
    output        debug_instr_valid,
    output        debug_fetch_restart,
    output        debug_data_ready,
    output        debug_interrupt_pending,
    output        debug_branch,
    output        debug_early_branch,
    output        debug_ret,
    output        debug_reg_wen,
    output        debug_counter_0,
    output        debug_data_continue,
    output        debug_stall_txn,
    output        debug_stop_txn,
    output  [3:0] debug_rd
);

  // CPU to memory controller wiring
  wire [23:1] instr_addr;
  wire        instr_fetch_restart;
  wire        instr_fetch_stall;
  wire        instr_fetch_started;
  wire        instr_fetch_stopped;
  wire [15:0] instr_data;
  wire        instr_ready;
  wire [27:0] qv_data_addr;
  wire  [1:0] qv_data_write_n;
  wire  [1:0] qv_data_read_n;
  wire        qv_data_read_complete;
  wire [31:0] qv_data_to_write;
  wire        qv_data_ready;
  wire [31:0] qv_data_from_read;
  wire        qv_data_continue;
  wire  [1:0] mem_data_write_n;
  wire  [1:0] mem_data_read_n;
  wire        mem_data_ready;
  wire [31:0] mem_data_from_read;

  wire is_mem = qv_data_addr[27:25] == 0;
  assign qv_data_ready = is_mem ? mem_data_ready : data_ready;
  assign qv_data_from_read = is_mem ? mem_data_from_read : data_in;

  assign mem_data_write_n = is_mem ? qv_data_write_n : 2'b11;
  assign mem_data_read_n =  is_mem ? qv_data_read_n  : 2'b11;

  assign data_addr = qv_data_addr;
  assign data_write_n =       !is_mem ? qv_data_write_n       : 2'b11;
  assign data_read_n =        !is_mem ? qv_data_read_n        : 2'b11;
  assign data_read_complete = !is_mem ? qv_data_read_complete : 0;
  assign data_out = qv_data_to_write;

  // Use a positive edge triggered reset for the CPU, to improve timing
  // The CPU doesn't use async reset.
  reg rst_reg_n;
  always @(posedge clk) rst_reg_n <= rstn;

  tinyqv_cpu cpu(
        .clk(clk),
        .rstn(rst_reg_n),

        .instr_addr(instr_addr),
        .instr_fetch_restart(instr_fetch_restart),
        .instr_fetch_stall(instr_fetch_stall),

        .instr_fetch_started(instr_fetch_started),
        .instr_fetch_stopped(instr_fetch_stopped),
        .instr_data_in(instr_data),
        .instr_ready(instr_ready),

        .interrupt_req(interrupt_req),

        .data_addr(qv_data_addr),
        .data_write_n(qv_data_write_n),
        .data_read_n(qv_data_read_n),
        .data_read_complete(qv_data_read_complete),
        .data_out(qv_data_to_write),
        .data_continue(qv_data_continue),

        .data_ready(qv_data_ready),
        .data_in(qv_data_from_read),

        .debug_instr_complete(debug_instr_complete),
        .debug_instr_valid(debug_instr_valid),
        .debug_interrupt_pending(debug_interrupt_pending),
        .debug_branch(debug_branch),
        .debug_early_branch(debug_early_branch),
        .debug_ret(debug_ret),
        .debug_reg_wen(debug_reg_wen),
        .debug_counter_0(debug_counter_0),
        .debug_rd(debug_rd)
    );

  tinyqv_mem_ctrl mem(
        .clk(clk),
        .rstn(rstn),

        .instr_addr(instr_addr),
        .instr_fetch_restart(instr_fetch_restart),
        .instr_fetch_stall(instr_fetch_stall),

        .instr_fetch_started(instr_fetch_started),
        .instr_fetch_stopped(instr_fetch_stopped),
        .instr_data(instr_data),
        .instr_ready(instr_ready),

        .data_addr(qv_data_addr[24:0]),
        .data_write_n(mem_data_write_n),
        .data_read_n(mem_data_read_n),
        .data_to_write(qv_data_to_write),
        .data_continue(qv_data_continue),

        .data_ready(mem_data_ready),
        .data_from_read(mem_data_from_read),

        .spi_data_in(spi_data_in),
        .spi_data_out(spi_data_out),
        .spi_data_oe(spi_data_oe),
        .spi_flash_select(spi_flash_select),
        .spi_ram_a_select(spi_ram_a_select),
        .spi_ram_b_select(spi_ram_b_select),
        .spi_clk_out(spi_clk_out),

        .debug_stall_txn(debug_stall_txn),
        .debug_stop_txn(debug_stop_txn)
    );

    assign debug_instr_ready = instr_ready;
    assign debug_fetch_restart = instr_fetch_restart;
    assign debug_data_ready = qv_data_ready;
    assign debug_data_continue = qv_data_continue;

endmodule
