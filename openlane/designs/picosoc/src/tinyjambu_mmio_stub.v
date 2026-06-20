`default_nettype none
(* blackbox *)
module tinyjambu_mmio (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         wr_en,
    input  wire [7:0]   reg_addr,
    input  wire [31:0]  reg_wdata,
    output wire [31:0]  reg_rdata
);
endmodule

