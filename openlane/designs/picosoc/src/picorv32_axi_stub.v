`default_nettype none
/* Blackbox stub for picorv32_axi hardened macro */
(* blackbox *)
module picorv32_axi (
`ifdef USE_POWER_PINS
    inout  wire          VPWR,
    inout  wire          VGND,
`endif
    input  wire          clk,
    input  wire          resetn,
    output wire          trap,

    // AXI4-lite master memory interface
    output wire          mem_axi_awvalid,
    input  wire          mem_axi_awready,
    output wire [31:0]   mem_axi_awaddr,
    output wire [ 2:0]   mem_axi_awprot,

    output wire          mem_axi_wvalid,
    input  wire          mem_axi_wready,
    output wire [31:0]   mem_axi_wdata,
    output wire [ 3:0]   mem_axi_wstrb,

    input  wire          mem_axi_bvalid,
    output wire          mem_axi_bready,

    output wire          mem_axi_arvalid,
    input  wire          mem_axi_arready,
    output wire [31:0]   mem_axi_araddr,
    output wire [ 2:0]   mem_axi_arprot,

    input  wire          mem_axi_rvalid,
    output wire          mem_axi_rready,
    input  wire [31:0]   mem_axi_rdata,

    // Pico Co-Processor Interface (PCPI)
    output wire          pcpi_valid,
    output wire [31:0]   pcpi_insn,
    output wire [31:0]   pcpi_rs1,
    output wire [31:0]   pcpi_rs2,
    input  wire          pcpi_wr,
    input  wire [31:0]   pcpi_rd,
    input  wire          pcpi_wait,
    input  wire          pcpi_ready,

    // IRQ interface
    input  wire [31:0]   irq,
    output wire [31:0]   eoi,

    // Trace Interface
    output wire          trace_valid,
    output wire [35:0]   trace_data
);
endmodule
