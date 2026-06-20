// =============================================================================
//  tinyjambu_paper_32.v  (tối ưu LUT)
//  TinyJAMBU-128 — Kiến trúc 4 khối, controller gọn
//
//  Tối ưu so với bản trước:
//   - Controller expose state[3:0] trực tiếp, bỏ phase_out + word_sel
//   - Chuyển num_ad/data_words, ad/data_vb, data MUX ra top module
//   - Top module dùng state trực tiếp chọn dữ liệu (giống code gốc)
// =============================================================================
`timescale 1ns/1ps

// FSM states (dùng chung)
`define S_IDLE          4'd0
`define S_LD_INIT_STATE 4'd1
`define S_LOAD_KEY      4'd2
`define S_INIT_KEY      4'd3
`define S_WAIT_NPUB     4'd4
`define S_LD_NPUB       4'd5
`define S_LD_NPUB_1     4'd6
`define S_WAIT_BDI      4'd7
`define S_PROC_AD_0     4'd8
`define S_PROC_AD_1     4'd9
`define S_PROC_PT_0     4'd10
`define S_PROC_PT_1     4'd11
`define S_FINAL         4'd12
`define S_FINAL2        4'd13
`define S_FINAL3        4'd14
`define S_DONE          4'd15

// =============================================================================
// KHỐI 1: NLFSR 32-bit
// =============================================================================
module tinyjambu_nlfsr_32 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         en,
    input  wire [1:0]   sel,
    input  wire         frame_en,
    input  wire [31:0]  absorb_data,
    input  wire [2:0]   frame_bits,
    input  wire [1:0]   len_val,
    input  wire [31:0]  key_word,
    output wire [127:0] s_out,
    output wire [31:0]  u_word
);
    reg [127:0] s;

    assign u_word = s[122:91]
                  ^ (~(s[116:85] & s[101:70]))
                  ^ s[78:47]
                  ^ s[31:0]
                  ^ key_word;

    wire [31:0] word_in =
        (sel == 2'b11) ? 32'h0        :
        (sel == 2'b10) ? absorb_data  : u_word;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s <= 128'h0;
        end else if (en) begin
            s[127:96] <= word_in;
            s[95:0]   <= s[127:32];
        end else if (frame_en) begin
            s[38:36] <= s[38:36] ^ frame_bits;
            s[33:32] <= s[33:32] ^ len_val;
        end
    end

    assign s_out = s;
endmodule

// =============================================================================
// KHỐI 2: KeyReg 32-bit
// =============================================================================
module tinyjambu_keyreg_32 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         load_en,
    input  wire         shift_en,
    input  wire [127:0] key_data,
    output wire [31:0]  key_word
);
    reg [127:0] key_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          key_reg <= 128'h0;
        else if (load_en)    key_reg <= key_data;
        else if (shift_en)   key_reg <= {key_reg[31:0], key_reg[127:32]};
    end

    assign key_word = key_reg[31:0];
endmodule

// =============================================================================
// KHỐI 3: Comb 32-bit
// =============================================================================
module tinyjambu_comb_32 (
    input  wire [127:0] s,
    input  wire [31:0]  u_word,
    input  wire [31:0]  data_le,
    input  wire         decrypt,
    input  wire [3:0]   valid_bytes,
    input  wire         is_pt_phase,
    output wire [31:0]  new_st,
    output wire [31:0]  out_word_le,
    output wire [31:0]  tag_word
);
    wire [31:0] xor_out = s[127:96] ^ data_le;

    wire [31:0] xor_filt = {
        xor_out[31:24] & {8{valid_bytes[0]}},
        xor_out[23:16] & {8{valid_bytes[1]}},
        xor_out[15:8]  & {8{valid_bytes[2]}},
        xor_out[7:0]   & {8{valid_bytes[3]}}
    };

    assign out_word_le = xor_filt;
    wire [31:0] in_word = (decrypt && is_pt_phase) ? xor_filt : data_le;
    assign new_st  = u_word ^ in_word;
    assign tag_word = s[127:96];
endmodule

// =============================================================================
// KHỐI 4: Controller gọn
//   - Bỏ phase_out, word_sel, num_ad/data_words, ad/data_vb
//   - Expose state_out + counters
//   - Nhận num_ad/data_words, ad/data_vb từ top
// =============================================================================
module tinyjambu_ctrl_32 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         ena,
    input  wire         decrypt_in,
    input  wire [2:0]   num_ad_words,
    input  wire [2:0]   num_data_words,
    input  wire [1:0]   ad_vb_in,
    input  wire [1:0]   data_vb_in,
    input  wire         tag_mismatch,
    // NLFSR
    output reg          nlfsr_en,
    output reg  [1:0]   nlfsr_sel,
    output reg          nlfsr_frame,
    output reg  [2:0]   frame_bits,
    output reg  [1:0]   len_val_out,
    // KeyReg
    output reg          key_load,
    output reg          key_shift,
    // Tag
    output reg          capture_tag,
    output reg  [1:0]   tag_half,
    // Expose
    output wire [3:0]   state_out,
    output reg          decrypt_r,
    output reg          done_o,
    output reg          valid_o,
    output wire [1:0]   npub_cnt_out,
    output wire [1:0]   ad_cnt_out,
    output wire [1:0]   data_cnt_out
);

    reg [3:0]  state, nstate;
    reg [5:0]  ctr;
    reg [1:0]  npub_cnt;
    reg [2:0]  ad_cnt;
    reg [2:0]  data_cnt;
    reg        auth_fail;
    reg [1:0]  len_val_r;
    reg        rst_ctr, en_ctr, en_len;
    reg [1:0]  nlen;

    assign state_out    = state;
    assign npub_cnt_out = npub_cnt;
    assign ad_cnt_out   = ad_cnt[1:0];
    assign data_cnt_out = data_cnt[1:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= `S_IDLE;
        else        state <= nstate;
    end

    always @(*) begin
        nstate      = state;
        rst_ctr     = 1'b0;  en_ctr      = 1'b0;
        nlfsr_en    = 1'b0;  nlfsr_sel   = 2'b00;
        nlfsr_frame = 1'b0;  frame_bits  = 3'b000;
        len_val_out = 2'b00;
        key_load    = 1'b0;  key_shift   = 1'b0;
        capture_tag = 1'b0;  tag_half    = 2'b00;
        en_len      = 1'b0;  nlen        = 2'b00;

        case (state)
            `S_IDLE: if (ena) begin nstate = `S_LD_INIT_STATE; rst_ctr = 1'b1; end

            `S_LD_INIT_STATE: begin
                nlfsr_sel = 2'b11; nlfsr_en = 1'b1; en_ctr = 1'b1;
                if (ctr == 6'd3) begin nstate = `S_LOAD_KEY; rst_ctr = 1'b1; end
            end

            `S_LOAD_KEY: begin key_load = 1'b1; nstate = `S_INIT_KEY; rst_ctr = 1'b1; end

            `S_INIT_KEY: begin
                nlfsr_en = 1'b1; key_shift = 1'b1; en_ctr = 1'b1;
                if (ctr == 6'd31) nstate = `S_WAIT_NPUB;
            end

            `S_WAIT_NPUB: begin
                if (npub_cnt != 2'd3) begin
                    nlfsr_frame = 1'b1; frame_bits = 3'b001;
                    rst_ctr = 1'b1; nstate = `S_LD_NPUB;
                end else nstate = `S_WAIT_BDI;
            end

            `S_LD_NPUB: begin
                nlfsr_en = 1'b1; key_shift = 1'b1; en_ctr = 1'b1;
                if (ctr == 6'd18) nstate = `S_LD_NPUB_1;
            end

            `S_LD_NPUB_1: begin
                nlfsr_sel = 2'b10; nlfsr_en = 1'b1; key_shift = 1'b1;
                en_ctr = 1'b1; nstate = `S_WAIT_NPUB;
            end

            `S_WAIT_BDI: begin
                rst_ctr = 1'b1;
                if (ad_cnt < num_ad_words) begin
                    nlfsr_frame = 1'b1; frame_bits = 3'b011;
                    len_val_out = len_val_r; nstate = `S_PROC_AD_0;
                end else if (data_cnt < num_data_words) begin
                    nlfsr_frame = 1'b1; frame_bits = 3'b101;
                    len_val_out = len_val_r; nstate = `S_PROC_PT_0;
                end else begin
                    nlfsr_frame = 1'b1; frame_bits = 3'b111;
                    len_val_out = len_val_r;
                    en_len = 1'b1; nlen = 2'b00; nstate = `S_FINAL;
                end
            end

            `S_PROC_AD_0: begin
                nlfsr_en = 1'b1; key_shift = 1'b1; en_ctr = 1'b1;
                if (ctr == 6'd18) nstate = `S_PROC_AD_1;
            end

            `S_PROC_AD_1: begin
                nlfsr_sel = 2'b10; nlfsr_en = 1'b1; key_shift = 1'b1;
                en_ctr = 1'b1; en_len = 1'b1; nlen = ad_vb_in;
                nstate = `S_WAIT_BDI;
            end

            `S_PROC_PT_0: begin
                nlfsr_en = 1'b1; key_shift = 1'b1; en_ctr = 1'b1;
                if (ctr == 6'd30) nstate = `S_PROC_PT_1;
            end

            `S_PROC_PT_1: begin
                nlfsr_sel = 2'b10; nlfsr_en = 1'b1; key_shift = 1'b1;
                en_ctr = 1'b1; en_len = 1'b1; nlen = data_vb_in;
                nstate = `S_WAIT_BDI;
            end

            `S_FINAL: begin
                nlfsr_en = 1'b1; key_shift = 1'b1; en_ctr = 1'b1;
                if (ctr == 6'd31) begin
                    capture_tag = 1'b1; tag_half = 2'b01; nstate = `S_FINAL2;
                end
            end

            `S_FINAL2: begin
                nlfsr_frame = 1'b1; frame_bits = 3'b111;
                rst_ctr = 1'b1; nstate = `S_FINAL3;
            end

            `S_FINAL3: begin
                nlfsr_en = 1'b1; key_shift = 1'b1; en_ctr = 1'b1;
                if (ctr == 6'd19) begin
                    capture_tag = 1'b1; tag_half = 2'b10;
                    nstate = `S_DONE; rst_ctr = 1'b1;
                end
            end

            `S_DONE: nstate = `S_IDLE;
            default: nstate = `S_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctr <= 6'd0; npub_cnt <= 2'd0; ad_cnt <= 3'd0; data_cnt <= 3'd0;
            decrypt_r <= 1'b0; auth_fail <= 1'b0; len_val_r <= 2'b00;
            done_o <= 1'b0; valid_o <= 1'b0;
        end else begin
            done_o <= 1'b0; valid_o <= 1'b0;

            if (state == `S_IDLE && nstate == `S_LD_INIT_STATE) begin
                decrypt_r <= decrypt_in; auth_fail <= 1'b0;
                npub_cnt <= 2'd0; ad_cnt <= 3'd0; data_cnt <= 3'd0;
                len_val_r <= 2'b00;
            end

            if (rst_ctr) ctr <= 6'd0; else if (en_ctr) ctr <= ctr + 6'd1;
            if (en_len) len_val_r <= nlen;

            if (state == `S_LD_NPUB_1)  npub_cnt <= npub_cnt + 2'd1;
            if (state == `S_PROC_AD_1)  ad_cnt   <= ad_cnt + 3'd1;
            if (state == `S_PROC_PT_1)  data_cnt <= data_cnt + 3'd1;

            if (capture_tag && decrypt_r && tag_mismatch) auth_fail <= 1'b1;

            if (state == `S_DONE) begin done_o <= 1'b1; valid_o <= ~auth_fail; end
        end
    end
endmodule

// =============================================================================
// KHỐI 5: Top — dùng state trực tiếp (giống code gốc)
// =============================================================================
module tinyjambu_core(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         ena,
    input  wire [2:0]   sel_type,
    input  wire [127:0] key,
    input  wire [95:0]  nonce,
    input  wire [127:0] ad,
    input  wire [4:0]   ad_length,
    input  wire [4:0]   data_length,
    input  wire [127:0] data_in,
    input  wire [63:0]  tag_in,
    output reg          valid,
    output reg  [63:0]  tag,
    output reg  [127:0] data_out,
    output reg          done
);
    function [31:0] bswap32;
        input [31:0] x;
        bswap32 = {x[7:0], x[15:8], x[23:16], x[31:24]};
    endfunction

    // Dây nối
    wire        nlfsr_en, nlfsr_frame, key_load_en, key_shift_en;
    wire [1:0]  nlfsr_sel;
    wire [2:0]  ctrl_frame_bits;
    wire [1:0]  ctrl_len_val;
    wire        ctrl_cap_tag, ctrl_decrypt, ctrl_done, ctrl_valid;
    wire [1:0]  ctrl_tag_half;
    wire [3:0]  st;
    wire [1:0]  npub_cnt, ad_cnt, data_cnt;
    wire [127:0] s_state;
    wire [31:0]  u_word, key_word;
    wire [31:0]  new_st, comb_out_le, comb_tag_word;

    // --- Tính toán (đã chuyển ra từ controller) ---
    wire [2:0] num_ad_words =
        (ad_length == 5'd0) ? 3'd0 : (ad_length <= 5'd4) ? 3'd1 :
        (ad_length <= 5'd8) ? 3'd2 : (ad_length <= 5'd12) ? 3'd3 : 3'd4;

    wire [2:0] num_data_words =
        (data_length == 5'd0) ? 3'd0 : (data_length <= 5'd4) ? 3'd1 :
        (data_length <= 5'd8) ? 3'd2 : (data_length <= 5'd12) ? 3'd3 : 3'd4;

    wire [4:0] ad_rem   = ad_length   - {1'b0, ad_cnt,   2'b00};
    wire [4:0] data_rem = data_length - {1'b0, data_cnt, 2'b00};
    wire [2:0] ad_vb    = (ad_rem   >= 5'd4) ? 3'd4 : ad_rem[2:0];
    wire [2:0] data_vb  = (data_rem >= 5'd4) ? 3'd4 : data_rem[2:0];

    // --- Khóa (thứ tự đảo, khớp shift-load gốc) ---
    wire [127:0] key_le = {
        bswap32(key[31:0]), bswap32(key[63:32]),
        bswap32(key[95:64]), bswap32(key[127:96])
    };

    // --- Chọn dữ liệu trực tiếp từ state (giống code gốc) ---
    wire [31:0] npub_word_be =
        (npub_cnt == 2'd0) ? nonce[95:64] :
        (npub_cnt == 2'd1) ? nonce[63:32] : nonce[31:0];

    wire [31:0] ad_word_be =
        (ad_cnt == 2'd0) ? ad[127:96] : (ad_cnt == 2'd1) ? ad[95:64] :
        (ad_cnt == 2'd2) ? ad[63:32]  : ad[31:0];

    wire [31:0] data_word_be =
        (data_cnt == 2'd0) ? data_in[127:96] : (data_cnt == 2'd1) ? data_in[95:64] :
        (data_cnt == 2'd2) ? data_in[63:32]  : data_in[31:0];

    // bdi: chọn theo state trực tiếp
    wire [31:0] bdi_be =
        (st == `S_LD_NPUB_1) ? npub_word_be :
        (st == `S_PROC_AD_1) ? ad_word_be   :
        (st == `S_PROC_PT_1) ? data_word_be : 32'h0;

    wire [2:0] cur_vb =
        (st == `S_PROC_AD_1) ? ad_vb  :
        (st == `S_PROC_PT_1) ? data_vb : 3'd4;

    wire [31:0] bdi_be_msk =
        (cur_vb >= 3'd4) ? bdi_be :
        (cur_vb == 3'd3) ? {bdi_be[31:8],  8'h00} :
        (cur_vb == 3'd2) ? {bdi_be[31:16], 16'h0000} :
        (cur_vb == 3'd1) ? {bdi_be[31:24], 24'h000000} : 32'h0;

    wire [31:0] bdi_le = bswap32(bdi_be_msk);

    wire [3:0] data_vbm = {data_vb >= 3'd1, data_vb >= 3'd2,
                           data_vb >= 3'd3, data_vb >= 3'd4};
    wire [3:0] comb_vbm = (st == `S_PROC_PT_1) ? data_vbm : 4'hF;

    wire is_pt    = (st == `S_PROC_PT_1);
    wire cap_out  = (st == `S_PROC_PT_1);
    wire [1:0] word_idx =
        (st == `S_LD_NPUB || st == `S_LD_NPUB_1) ? npub_cnt :
        (st == `S_PROC_AD_0 || st == `S_PROC_AD_1) ? ad_cnt : data_cnt;

    // --- Tag compare ---
    wire [31:0] tag_rx0_le = bswap32(tag_in[63:32]);
    wire [31:0] tag_rx1_le = bswap32(tag_in[31:0]);
    wire tag_mismatch =
        (ctrl_tag_half == 2'b01) ? (comb_tag_word != tag_rx0_le) :
        (ctrl_tag_half == 2'b10) ? (comb_tag_word != tag_rx1_le) : 1'b0;

    // --- Instances ---
    tinyjambu_nlfsr_32 u_nlfsr (
        .clk(clk), .rst_n(rst_n), .en(nlfsr_en), .sel(nlfsr_sel),
        .frame_en(nlfsr_frame), .absorb_data(new_st),
        .frame_bits(ctrl_frame_bits), .len_val(ctrl_len_val),
        .key_word(key_word), .s_out(s_state), .u_word(u_word)
    );

    tinyjambu_keyreg_32 u_keyreg (
        .clk(clk), .rst_n(rst_n), .load_en(key_load_en),
        .shift_en(key_shift_en), .key_data(key_le), .key_word(key_word)
    );

    tinyjambu_comb_32 u_comb (
        .s(s_state), .u_word(u_word), .data_le(bdi_le),
        .decrypt(ctrl_decrypt), .valid_bytes(comb_vbm),
        .is_pt_phase(is_pt), .new_st(new_st),
        .out_word_le(comb_out_le), .tag_word(comb_tag_word)
    );

    tinyjambu_ctrl_32 u_ctrl (
        .clk(clk), .rst_n(rst_n), .ena(ena), .decrypt_in(sel_type[0]),
        .num_ad_words(num_ad_words), .num_data_words(num_data_words),
        .ad_vb_in(ad_vb[1:0]), .data_vb_in(data_vb[1:0]),
        .tag_mismatch(tag_mismatch),
        .nlfsr_en(nlfsr_en), .nlfsr_sel(nlfsr_sel),
        .nlfsr_frame(nlfsr_frame), .frame_bits(ctrl_frame_bits),
        .len_val_out(ctrl_len_val),
        .key_load(key_load_en), .key_shift(key_shift_en),
        .capture_tag(ctrl_cap_tag), .tag_half(ctrl_tag_half),
        .state_out(st), .decrypt_r(ctrl_decrypt),
        .done_o(ctrl_done), .valid_o(ctrl_valid),
        .npub_cnt_out(npub_cnt), .ad_cnt_out(ad_cnt), .data_cnt_out(data_cnt)
    );

    // --- Output registers ---
    reg [31:0] tag_w0_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out <= 128'h0; tag <= 64'h0; tag_w0_r <= 32'h0;
            done <= 1'b0; valid <= 1'b0;
        end else begin
            done <= 1'b0; valid <= 1'b0;

            if (cap_out) begin
                case (word_idx)
                    2'd0: data_out[127:96] <= bswap32(comb_out_le);
                    2'd1: data_out[95:64]  <= bswap32(comb_out_le);
                    2'd2: data_out[63:32]  <= bswap32(comb_out_le);
                    2'd3: data_out[31:0]   <= bswap32(comb_out_le);
                endcase
            end

            if (ctrl_cap_tag) begin
                if (ctrl_tag_half == 2'b01 && !ctrl_decrypt)
                    tag_w0_r <= comb_tag_word;
                if (ctrl_tag_half == 2'b10 && !ctrl_decrypt)
                    tag <= {bswap32(tag_w0_r), bswap32(comb_tag_word)};
            end

            if (ctrl_done) begin done <= 1'b1; valid <= ctrl_valid; end
        end
    end
endmodule
