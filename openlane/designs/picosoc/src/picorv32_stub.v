`default_nettype none
/* Blackbox stub for picorv32 hardened macro */
module picorv32 (
`ifdef USE_POWER_PINS
    inout  wire          VPWR,
    inout  wire          VGND,
`endif
    input  wire          clk,
    input  wire          resetn,
    output wire          trap,

    output wire          mem_valid,
    output wire          mem_instr,
    input  wire          mem_ready,
    output wire [31:0]   mem_addr,
    output wire [31:0]   mem_wdata,
    output wire [ 3:0]   mem_wstrb,
    input  wire [31:0]   mem_rdata,

    output wire          mem_la_read,
    output wire          mem_la_write,
    output wire [31:0]   mem_la_addr,
    output wire [31:0]   mem_la_wdata,
    output wire [ 3:0]   mem_la_wstrb,

    output wire          pcpi_valid,
    output wire [31:0]   pcpi_insn,
    output wire [31:0]   pcpi_rs1,
    output wire [31:0]   pcpi_rs2,
    input  wire          pcpi_wr,
    input  wire [31:0]   pcpi_rd,
    input  wire          pcpi_wait,
    input  wire          pcpi_ready,

    input  wire [31:0]   irq,
    output wire [31:0]   eoi,

    output wire          trace_valid,
    output wire [35:0]   trace_data
);
endmodule
