`timescale 1ns/1ps
// ============================================================
// crypto_cluster.v — shared APB slave for 3 AEAD cores
// ============================================================
// ctrl register (addr 0x000):
//   [1:0]  alg_sel    : 00=TinyJAMBU  01=Xoodyak  10=GIFT-COFB
//   [2]    start      : write 1 to trigger (auto-clears next cycle)
//   [3]    decrypt    : 0=encrypt  1=decrypt
//   [6]    done       : read-only sticky done flag
//   [7]    valid      : read-only sticky valid flag
//
// Shared input registers (word-aligned, PADDR[9:2] = word index):
//   0x04–0x10  key[127:0]        words 1–4
//   0x14–0x20  nonce[127:0]      words 5–8   (TinyJAMBU uses [95:0])
//   0x24–0x30  ad[127:0]         words 9–12
//   0x34–0x40  data_in[127:0]    words 13–16
//   0x44–0x50  tag_in[127:0]     words 17–20 (TinyJAMBU uses [63:0])
//   0x54       ad_len[7:0]       word 21
//   0x58       data_len[7:0]     word 22
//   0x5C       msg_len[7:0]      word 23
//   0x60       stream_status     word 24 [4]=gf_valid [3]=gf_done
//                                          [2]=gf_ad_req [1]=gf_msg_req
//                                          [0]=gf_data_valid_sticky
//   0x64       stream_ctrl       word 25 write [2]=clr_data_valid
//                                          [1]=ad_ack pulse [0]=msg_ack pulse
//
// Output readback:
//   0x80–0x8C  data_out[127:0]   words 32–35
//   0x90–0x9C  tag_out[127:0]    words 36–39
//   0xA0       meas_status       word 40 [2:1]=active_alg [0]=active
//   0xA4       meas_cycles_cur   word 41
//   0xA8       meas_cycles_last  word 42
//   0xAC       tinyjambu_cycles  word 43
//   0xB0       xoodyak_cycles    word 44
//   0xB4       giftcofb_cycles   word 45
// ============================================================

module crypto_cluster #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 32
)(
    input  wire                   PCLK,
    input  wire                   PRESETn,
    input  wire [ADDR_WIDTH-1:0]  PADDR,
    input  wire                   PSEL,
    input  wire                   PENABLE,
    input  wire                   PWRITE,
    input  wire [DATA_WIDTH-1:0]  PWDATA,
    output reg  [DATA_WIDTH-1:0]  PRDATA,
    output wire                   PREADY,
    output wire                   PSLVERR
);
    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    // -------------------------------------------------------
    // Control & shared input registers
    // -------------------------------------------------------
    reg [1:0] reg_alg_sel;
    reg       reg_decrypt;
    reg       start_pulse;

    reg [127:0] reg_key;
    reg [127:0] reg_nonce;
    reg [127:0] reg_ad;
    reg [127:0] reg_data_in;
    reg [127:0] reg_tag_in;
    reg [7:0]   reg_ad_len;
    reg [7:0]   reg_data_len;
    reg [7:0]   reg_msg_len;
    reg         ad_ack_pulse, msg_ack_pulse;
    reg         gf_data_valid_sticky;

    wire apb_wr   = PSEL && PENABLE && PWRITE;
    wire [7:0] wi = PADDR[9:2];    // word index

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            reg_alg_sel  <= 2'b00;
            reg_decrypt  <= 1'b0;
            start_pulse  <= 1'b0;
            reg_key      <= 128'b0;
            reg_nonce    <= 128'b0;
            reg_ad       <= 128'b0;
            reg_data_in  <= 128'b0;
            reg_tag_in   <= 128'b0;
            reg_ad_len   <= 8'd0;
            reg_data_len <= 8'd0;
            reg_msg_len  <= 8'd0;
            ad_ack_pulse <= 1'b0;
            msg_ack_pulse <= 1'b0;
        end else begin
            start_pulse <= 1'b0;          // auto-clear every cycle
            ad_ack_pulse <= 1'b0;
            msg_ack_pulse <= 1'b0;
            if (apb_wr) begin
                case (wi)
                    8'h00: begin
                        reg_alg_sel <= PWDATA[1:0];
                        start_pulse <= PWDATA[2];
                        reg_decrypt <= PWDATA[3];
                    end
                    8'h01: reg_key[  31:  0] <= PWDATA;
                    8'h02: reg_key[  63: 32] <= PWDATA;
                    8'h03: reg_key[  95: 64] <= PWDATA;
                    8'h04: reg_key[ 127: 96] <= PWDATA;
                    8'h05: reg_nonce[  31:  0] <= PWDATA;
                    8'h06: reg_nonce[  63: 32] <= PWDATA;
                    8'h07: reg_nonce[  95: 64] <= PWDATA;
                    8'h08: reg_nonce[ 127: 96] <= PWDATA;
                    8'h09: reg_ad[   31:  0] <= PWDATA;
                    8'h0A: reg_ad[   63: 32] <= PWDATA;
                    8'h0B: reg_ad[   95: 64] <= PWDATA;
                    8'h0C: reg_ad[  127: 96] <= PWDATA;
                    8'h0D: reg_data_in[  31:  0] <= PWDATA;
                    8'h0E: reg_data_in[  63: 32] <= PWDATA;
                    8'h0F: reg_data_in[  95: 64] <= PWDATA;
                    8'h10: reg_data_in[ 127: 96] <= PWDATA;
                    8'h11: reg_tag_in[  31:  0] <= PWDATA;
                    8'h12: reg_tag_in[  63: 32] <= PWDATA;
                    8'h13: reg_tag_in[  95: 64] <= PWDATA;
                    8'h14: reg_tag_in[ 127: 96] <= PWDATA;
                    8'h15: reg_ad_len   <= PWDATA[7:0];
                    8'h16: reg_data_len <= PWDATA[7:0];
                    8'h17: reg_msg_len  <= PWDATA[7:0];
                    8'h19: begin
                        msg_ack_pulse <= PWDATA[0];
                        ad_ack_pulse  <= PWDATA[1];
                    end
                    default: ;
                endcase
            end
        end
    end

    // -------------------------------------------------------
    // Core 0: TinyJAMBU   (nonce=96b, tag=64b)
    // -------------------------------------------------------
    wire [127:0] tj_data_out;
    wire [63:0]  tj_tag_out;
    wire         tj_valid, tj_done;

    tinyjambu_core u_tinyjambu (
`ifdef USE_POWER_PINS
        .VPWR(VPWR), .VGND(VGND),
`endif
        .clk        (PCLK),
        .rst_n      (PRESETn),
        .ena        (start_pulse && (reg_alg_sel == 2'b00)),
        .sel_type   (reg_decrypt ? 3'b001 : 3'b000),
        .key        (reg_key),
        .nonce      (reg_nonce[95:0]),
        .ad         (reg_ad),
        .ad_length  (reg_ad_len[4:0]),
        .data_in    (reg_data_in),
        .data_length(reg_data_len[4:0]),
        .tag_in     (reg_tag_in[63:0]),
        .data_out   (tj_data_out),
        .tag        (tj_tag_out),
        .valid      (tj_valid),
        .done       (tj_done)
    );

    // -------------------------------------------------------
    // Core 1: Xoodyak   (nonce=128b, tag=128b)
    // -------------------------------------------------------
    wire [127:0] xd_data_out, xd_tag_out;
    wire         xd_valid, xd_done;

    xoodyakcore u_xoodyak (
`ifdef USE_POWER_PINS
        .VPWR(VPWR), .VGND(VGND),
`endif
        .clk        (PCLK),
        .rst_n      (PRESETn),
        .ena        (start_pulse && (reg_alg_sel == 2'b01)),
        .restart    (1'b0),
        .sel_type   (reg_decrypt ? 2'b10 : 2'b01),
        .key        (reg_key),
        .nonce      (reg_nonce),
        .ad         (reg_ad),
        .ad_length  (reg_ad_len[4:0]),
        .data_length(reg_data_len[4:0]),
        .data_in    (reg_data_in),
        .tag_in     (reg_tag_in),
        .data_out   (xd_data_out),
        .tag        (xd_tag_out),
        .valid      (xd_valid),
        .done       (xd_done)
    );

    // -------------------------------------------------------
    // Core 2: GIFT-COFB  (nonce=128b, tag=128b, req/ack)
    // -------------------------------------------------------
    wire [127:0] gf_data_out, gf_tag_out;
    wire         gf_valid, gf_done;
    wire         gf_ad_req, gf_msg_req, gf_data_out_valid;

    cofb_core u_cofb (
`ifdef USE_POWER_PINS
        .VPWR(VPWR), .VGND(VGND),
`endif
        .clk          (PCLK),
        .rst_n        (PRESETn),
        .start        (start_pulse && (reg_alg_sel == 2'b10)),
        .decrypt_mode (reg_decrypt),
        .key          (reg_key),
        .nonce        (reg_nonce),
        .ad_data      (reg_ad),
        .ad_total_len (reg_ad_len),
        .ad_ack       (ad_ack_pulse),
        .msg_data     (reg_data_in),
        .msg_total_len(reg_msg_len),
        .msg_ack      (msg_ack_pulse),
        .tag_in       (reg_tag_in),
        .ad_req       (gf_ad_req),
        .msg_req      (gf_msg_req),
        .data_out     (gf_data_out),
        .data_out_valid(gf_data_out_valid),
        .tag_out      (gf_tag_out),
        .valid        (gf_valid),
        .done         (gf_done)
    );

    // -------------------------------------------------------
    // Output mux — select based on alg_sel
    // -------------------------------------------------------
    wire [127:0] sel_data_out = (reg_alg_sel == 2'b00) ? tj_data_out :
                                (reg_alg_sel == 2'b01) ? xd_data_out : gf_data_out;
    wire [127:0] sel_tag_out  = (reg_alg_sel == 2'b00) ? {64'b0, tj_tag_out} :
                                (reg_alg_sel == 2'b01) ? xd_tag_out  : gf_tag_out;
    wire         sel_done     = (reg_alg_sel == 2'b00) ? tj_done  :
                                (reg_alg_sel == 2'b01) ? xd_done  : gf_done;
    wire         sel_valid    = (reg_alg_sel == 2'b00) ? tj_valid :
                                (reg_alg_sel == 2'b01) ? xd_valid : gf_valid;

    // -------------------------------------------------------
    // Per-operation cycle measurement
    // Counts core cycles from start acceptance to done pulse.
    // -------------------------------------------------------
    reg        meas_active;
    reg [1:0]  meas_alg_sel;
    reg [31:0] meas_cycles_cur;
    reg [31:0] meas_cycles_last;
    reg [31:0] tj_cycles_last, xd_cycles_last, gf_cycles_last;

    wire meas_done = (meas_alg_sel == 2'b00) ? tj_done  :
                     (meas_alg_sel == 2'b01) ? xd_done  : gf_done;

    // -------------------------------------------------------
    // Done / valid sticky registers
    // -------------------------------------------------------
    reg done_sticky, valid_sticky;
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            done_sticky  <= 1'b0;
            valid_sticky <= 1'b0;
            gf_data_valid_sticky <= 1'b0;
        end else if (start_pulse) begin
            done_sticky  <= 1'b0;
            valid_sticky <= 1'b0;
            gf_data_valid_sticky <= 1'b0;
        end else if (sel_done) begin
            done_sticky  <= 1'b1;
            valid_sticky <= sel_valid;
        end else begin
            if (gf_data_out_valid)
                gf_data_valid_sticky <= 1'b1;
            if (apb_wr && wi == 8'h19 && PWDATA[2])
                gf_data_valid_sticky <= 1'b0;
        end
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            meas_active      <= 1'b0;
            meas_alg_sel     <= 2'b00;
            meas_cycles_cur  <= 32'd0;
            meas_cycles_last <= 32'd0;
            tj_cycles_last   <= 32'd0;
            xd_cycles_last   <= 32'd0;
            gf_cycles_last   <= 32'd0;
        end else if (start_pulse) begin
            meas_active     <= 1'b1;
            meas_alg_sel    <= reg_alg_sel;
            meas_cycles_cur <= 32'd0;
        end else if (meas_active) begin
            meas_cycles_cur <= meas_cycles_cur + 32'd1;
            if (meas_done) begin
                meas_active      <= 1'b0;
                meas_cycles_last <= meas_cycles_cur + 32'd1;
                case (meas_alg_sel)
                    2'b00: tj_cycles_last <= meas_cycles_cur + 32'd1;
                    2'b01: xd_cycles_last <= meas_cycles_cur + 32'd1;
                    default: gf_cycles_last <= meas_cycles_cur + 32'd1;
                endcase
            end
        end
    end

    // -------------------------------------------------------
    // APB read mux (combinational)
    // -------------------------------------------------------
    always @(*) begin
        case (wi)
            8'h00: PRDATA = {24'b0, valid_sticky, done_sticky,
                             1'b0, meas_active, reg_decrypt, 1'b0, reg_alg_sel};
            8'h01: PRDATA = reg_key[  31:  0];
            8'h02: PRDATA = reg_key[  63: 32];
            8'h03: PRDATA = reg_key[  95: 64];
            8'h04: PRDATA = reg_key[ 127: 96];
            8'h05: PRDATA = reg_nonce[  31:  0];
            8'h06: PRDATA = reg_nonce[  63: 32];
            8'h07: PRDATA = reg_nonce[  95: 64];
            8'h08: PRDATA = reg_nonce[ 127: 96];
            8'h09: PRDATA = reg_ad[   31:  0];
            8'h0A: PRDATA = reg_ad[   63: 32];
            8'h0B: PRDATA = reg_ad[   95: 64];
            8'h0C: PRDATA = reg_ad[  127: 96];
            8'h0D: PRDATA = reg_data_in[  31:  0];
            8'h0E: PRDATA = reg_data_in[  63: 32];
            8'h0F: PRDATA = reg_data_in[  95: 64];
            8'h10: PRDATA = reg_data_in[ 127: 96];
            8'h11: PRDATA = reg_tag_in[  31:  0];
            8'h12: PRDATA = reg_tag_in[  63: 32];
            8'h13: PRDATA = reg_tag_in[  95: 64];
            8'h14: PRDATA = reg_tag_in[ 127: 96];
            8'h15: PRDATA = {24'b0, reg_ad_len};
            8'h16: PRDATA = {24'b0, reg_data_len};
            8'h17: PRDATA = {24'b0, reg_msg_len};
            8'h18: PRDATA = {27'b0, gf_valid, gf_done, gf_ad_req,
                             gf_msg_req, gf_data_valid_sticky};
            8'h19: PRDATA = 32'h0;
            8'h20: PRDATA = sel_data_out[  31:  0];
            8'h21: PRDATA = sel_data_out[  63: 32];
            8'h22: PRDATA = sel_data_out[  95: 64];
            8'h23: PRDATA = sel_data_out[ 127: 96];
            8'h24: PRDATA = sel_tag_out[  31:  0];
            8'h25: PRDATA = sel_tag_out[  63: 32];
            8'h26: PRDATA = sel_tag_out[  95: 64];
            8'h27: PRDATA = sel_tag_out[ 127: 96];
            8'h28: PRDATA = {29'b0, meas_alg_sel, meas_active};
            8'h29: PRDATA = meas_cycles_cur;
            8'h2A: PRDATA = meas_cycles_last;
            8'h2B: PRDATA = tj_cycles_last;
            8'h2C: PRDATA = xd_cycles_last;
            8'h2D: PRDATA = gf_cycles_last;
            default: PRDATA = 32'h0;
        endcase
    end

endmodule

