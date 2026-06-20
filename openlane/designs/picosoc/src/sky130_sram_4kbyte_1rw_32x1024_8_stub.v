`define USE_POWER_PINS
(* blackbox *)
module sky130_sram_4kbyte_1rw_32x1024_8(
`ifdef USE_POWER_PINS
    vccd1,
    vssd1,
`endif
    clk0,
    csb0,
    web0,
    spare_wen0,
    addr0,
    din0,
    dout0
);
`ifdef USE_POWER_PINS
    inout  wire        vccd1;
    inout  wire        vssd1;
`endif
    input  wire        clk0;
    input  wire        csb0;
    input  wire        web0;
    input  wire        spare_wen0;
    input  wire [10:0] addr0;
    input  wire [32:0] din0;
    output wire [32:0] dout0;
endmodule
