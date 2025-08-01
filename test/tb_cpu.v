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
    input  [15:0] instr_data_in,
    input         instr_ready,

    input  [15:0] interrupt_req,
    input         time_pulse,

    output reg [27:0] data_addr,
    output reg [1:0]  data_write_n,
    output reg [1:0]  data_read_n,
    output            data_read_complete,
    output reg [31:0] data_out,

    output        data_continue,

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

    wire        debug_instr_complete;
    wire        debug_instr_valid;
    wire        debug_interrupt_pending;
    wire        debug_branch;
    wire        debug_early_branch;
    wire        debug_ret;
    wire        debug_reg_wen;
    wire        debug_counter_0;
    wire [3:0] debug_rd;

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

        interrupt_req,

        data_addr,
        data_write_n,
        data_read_n,
        data_read_complete,
        data_out,

        data_continue,

        data_ready,  // Transaction complete/data request can be modified.
        data_in,

        time_pulse,

        debug_instr_complete,
        debug_instr_valid,
        debug_interrupt_pending,
        debug_branch,
        debug_early_branch,
        debug_ret,
        debug_reg_wen,
        debug_counter_0,
        debug_rd        
    );

endmodule
