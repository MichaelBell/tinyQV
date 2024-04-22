`default_nettype none
`timescale 1ns / 100ps

/* A RISC-V core designed to use minimal area.
  
   Aim is to support RV32E 
 */

module tb_cpu (
    input clk,
    input rstn,

    output [23:1] instr_addr,
    output        instr_fetch_restart,
    output        instr_fetch_stall,

    input         instr_fetch_started,
    input         instr_fetch_stopped,
    input  [7:0] instr_data_in,
    input         instr_ready,

    output reg [27:0] data_addr,
    output reg [1:0]  data_write_n,
    output reg [1:0]  data_read_n,
    output reg [31:0] data_out,

    input         data_ready,  // Transaction complete/data request can be modified.
    input  [31:0] data_in
);

`ifdef COCOTB_SIM
initial begin
  $dumpfile ("cpu.vcd");
  $dumpvars (0, tb_cpu);
  #1;
end
`endif

    tinyqv_cpu cpu(
        clk,
        rstn,

        instr_addr,
        instr_fetch_restart,
        instr_fetch_stall,

        instr_fetch_started,
        instr_fetch_stopped,
        instr_data_in,
        instr_ready,

        data_addr,
        data_write_n,
        data_read_n,
        data_out,

        {{4{data_ready}}},  // Transaction complete/data request can be modified.
        data_in        
    );

endmodule