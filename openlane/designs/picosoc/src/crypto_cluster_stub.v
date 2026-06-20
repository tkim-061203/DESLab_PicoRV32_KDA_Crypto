(* blackbox *)
module crypto_cluster (
    input PCLK,
    input PENABLE,
    output PREADY,
    input PRESETn,
    input PSEL,
    output PSLVERR,
    input PWRITE,
`ifdef USE_POWER_PINS
    inout VGND,
    inout VPWR,
`endif
    input [11:0] PADDR,
    output [31:0] PRDATA,
    input [31:0] PWDATA
);
endmodule
