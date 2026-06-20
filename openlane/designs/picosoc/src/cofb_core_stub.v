`default_nettype none
/* Blackbox stub for cofb_core hardened macro */
(* blackbox *)
module cofb_core (
`ifdef USE_POWER_PINS
    inout  wire         VPWR,
    inout  wire         VGND,
`endif
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire         decrypt_mode,
    input  wire [127:0] key,
    input  wire [127:0] nonce,
    input  wire [127:0] ad_data,
    input  wire [7:0]   ad_total_len,
    input  wire         ad_ack,
    input  wire [127:0] msg_data,
    input  wire [7:0]   msg_total_len,
    input  wire         msg_ack,
    input  wire [127:0] tag_in,
    output wire         ad_req,
    output wire         msg_req,
    output wire [127:0] data_out,
    output wire         data_out_valid,
    output wire [127:0] tag_out,
    output wire         valid,
    output wire         done
);
endmodule
