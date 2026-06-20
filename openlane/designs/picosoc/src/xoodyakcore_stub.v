`default_nettype none
/* Blackbox stub for xoodyakcore hardened macro */
(* blackbox *)
module xoodyakcore (
`ifdef USE_POWER_PINS
    inout  wire          VPWR,
    inout  wire          VGND,
`endif
    input  wire          clk,
    input  wire          rst_n,
    input  wire          ena,
    input  wire          restart,
    input  wire [1:0]    sel_type,
    input  wire [127:0]  key,
    input  wire [127:0]  nonce,
    input  wire [127:0]  ad,
    input  wire [4:0]    ad_length,
    input  wire [4:0]    data_length,
    input  wire [127:0]  data_in,
    input  wire [127:0]  tag_in,
    output wire          valid,
    output wire [127:0]  tag,
    output wire [127:0]  data_out,
    output wire          done
);
endmodule
