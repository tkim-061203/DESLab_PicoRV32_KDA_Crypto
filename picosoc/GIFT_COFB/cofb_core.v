// ============================================================
// COFB CORE - Multi-block FSM (matching encrypt.c)
// Req/ack handshake interface for multi-block AD and MSG
// ============================================================

module cofb_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire         decrypt_mode,   // 0: Encrypt, 1: Decrypt

    input  wire [127:0] key,
    input  wire [127:0] nonce,

    // ---- AD streaming input ----
    input  wire [127:0] ad_data,
    input  wire [7:0]   ad_total_len,   // Total AD bytes (0..255)
    input  wire         ad_ack,         // User: new block is stable on ad_data

    // ---- MSG streaming input ----
    input  wire [127:0] msg_data,
    input  wire [7:0]   msg_total_len,  // Total MSG bytes (0..255)
    input  wire         msg_ack,        // User: new block is stable on msg_data

    // ---- Decrypt: tag to check ----
    input  wire [127:0] tag_in,

    // ---- Handshake outputs ----
    output reg          ad_req,         // Core is waiting for the next AD block
    output reg          msg_req,        // Core is waiting for the next MSG block

    // ---- Output streaming ----
    output reg  [127:0] data_out,
    output reg          data_out_valid,

    // ---- Final results ----
    output reg  [127:0] tag_out,
    output reg          valid,          // Decrypt: 1 if tag matches; Encrypt: always 1
    output reg          done
);

    // ----------------------------------------------------------
    // FSM States
    // ----------------------------------------------------------
    localparam S_IDLE       = 4'd0;
    localparam S_WAIT_NONCE = 4'd1;
    localparam S_PROC_AD    = 4'd2;
    localparam S_WAIT_AD    = 4'd3;
    localparam S_REQ_AD     = 4'd4;
    localparam S_PROC_MSG   = 4'd5;
    localparam S_WAIT_MSG   = 4'd6;
    localparam S_REQ_MSG    = 4'd7;
    localparam S_DONE       = 4'd8;

    reg [3:0]   state;
    reg [63:0]  L;
    reg [127:0] Y_prev;
    reg [7:0]   remaining_ad;
    reg [7:0]   remaining_msg;
    reg         is_last_ad;
    reg         is_last_msg;

    // ----------------------------------------------------------
    // Combinational signals
    // ----------------------------------------------------------
    wire [4:0] ad_bytes  = (remaining_ad  > 8'd16) ? 5'd16 : remaining_ad[4:0];
    wire [4:0] msg_bytes = (remaining_msg > 8'd16) ? 5'd16 : remaining_msg[4:0];

    wire last_ad_now  = (remaining_ad  <= 8'd16);
    wire last_msg_now = (remaining_msg <= 8'd16);

    // C: (alen%16 != 0) || emptyA
    wire partial_or_empty_ad = (remaining_ad == 8'd0) ||
                                (remaining_ad[3:0] != 4'd0);

    // C: inlen%16 != 0
    wire partial_msg = (remaining_msg != 8'd0) &&
                       (remaining_msg[3:0] != 4'd0);

    // emptyM: use original total length (input port, invariant)
    wire emptyM = (msg_total_len == 8'd0);

    // ----------------------------------------------------------
    // Submodule connections
    // ----------------------------------------------------------
    reg  [127:0] gift_in;
    wire [127:0] gift_out;
    reg          gift_start;
    wire         gift_done;

    wire [127:0] pho1_AD_X;
    wire [127:0] gift_in_with_offset;

    // ----------------------------------------------------------
    // Shared MSG processing (replaces separate pho + phoprime)
    // Both compute partial_xor(Y,input) and pho1(Y,M,bytes).
    // Encrypt: out_data=C=xor(Y,M), X=pho1(Y, M)
    // Decrypt: out_data=M=xor(Y,C), X=pho1(Y, M=xor(Y,C))
    // ----------------------------------------------------------
    wire [127:0] msg_xor_out;   // C (encrypt) or M (decrypt)
    wire [127:0] msg_pho1_X;    // chaining value for both modes

    xor_block u_msg_xor (
        .s1          (Y_prev),
        .s2          (msg_data),
        .no_of_bytes (msg_bytes),
        .d           (msg_xor_out)
    );

    // pho1 M input: encrypt uses msg_data, decrypt uses msg_xor_out
    wire [127:0] pho1_msg_m_in = decrypt_mode ? msg_xor_out : msg_data;

    pho1 u_pho1_msg (
        .Y_in        (Y_prev),
        .M_in        (pho1_msg_m_in),
        .no_of_bytes (msg_bytes),
        .d           (msg_pho1_X)
    );

    // ----------------------------------------------------------
    // Offset sequence: L → 2L / 3L / 9L / 27L / 81L
    // ----------------------------------------------------------
    wire [63:0] L_dbl;
    wire [63:0] L_tri;
    wire [63:0] L_tri2;
    wire [63:0] L_tri3;
    wire [63:0] L_tri4;

    double_half_block u_dbl  (.s(L),      .d(L_dbl));
    triple_half_block u_tri  (.s(L),      .d(L_tri));
    triple_half_block u_tri2 (.s(L_tri),  .d(L_tri2));
    triple_half_block u_tri3 (.s(L_tri2), .d(L_tri3));
    triple_half_block u_tri4 (.s(L_tri3), .d(L_tri4));

    pho1 u_pho1_ad (
        .Y_in        (Y_prev),
        .M_in        (ad_data),
        .no_of_bytes (ad_bytes),
        .d           (pho1_AD_X)
    );

    xor_topbar_block u_offset_xor (
        .s1 (gift_in),
        .s2 (L),
        .d  (gift_in_with_offset)
    );

    gift128_encrypt_top u_gift (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (gift_start),
        .plaintext (gift_in_with_offset),
        .key       (key),
        .busy      (),
        .done      (gift_done),
        .ciphertext(gift_out)
    );

    // ----------------------------------------------------------
    // FSM Sequential
    // ----------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            done           <= 1'b0;
            valid          <= 1'b0;
            data_out_valid <= 1'b0;
            ad_req         <= 1'b0;
            msg_req        <= 1'b0;
            gift_start     <= 1'b0;
            L              <= 64'd0;
            Y_prev         <= 128'd0;
            data_out       <= 128'd0;
            tag_out        <= 128'd0;
            gift_in        <= 128'd0;
            remaining_ad   <= 8'd0;
            remaining_msg  <= 8'd0;
            is_last_ad     <= 1'b0;
            is_last_msg    <= 1'b0;
        end else begin

            gift_start     <= 1'b0;
            data_out_valid <= 1'b0;
            ad_req         <= 1'b0;
            msg_req        <= 1'b0;

            case (state)

                // =================================================
                // S_IDLE
                // =================================================
                S_IDLE: begin
                    done  <= 1'b0;
                    valid <= 1'b0;
                    if (start) begin
                        gift_in       <= nonce;
                        L             <= 64'd0;
                        gift_start    <= 1'b1;
                        remaining_ad  <= ad_total_len;
                        remaining_msg <= msg_total_len;
                        state         <= S_WAIT_NONCE;
                    end
                end

                // =================================================
                // S_WAIT_NONCE
                // =================================================
                S_WAIT_NONCE: begin
                    if (gift_done) begin
                        Y_prev <= gift_out;
                        L      <= gift_out[127:64];
                        state  <= S_PROC_AD;
                    end
                end

                // =================================================
                // S_PROC_AD
                // =================================================
                S_PROC_AD: begin
                    is_last_ad <= last_ad_now;

                    if (!last_ad_now) begin
                        L <= L_dbl;
                    end else begin
                        if      (!partial_or_empty_ad && !emptyM) L <= L_tri;
                        else if ( partial_or_empty_ad && !emptyM) L <= L_tri2;
                        else if (!partial_or_empty_ad &&  emptyM) L <= L_tri3;
                        else                                       L <= L_tri4;
                    end

                    gift_in    <= pho1_AD_X;
                    gift_start <= 1'b1;
                    state      <= S_WAIT_AD;
                end

                // =================================================
                // S_WAIT_AD
                // =================================================
                S_WAIT_AD: begin
                    if (gift_done) begin
                        Y_prev <= gift_out;

                        if (is_last_ad) begin
                            if (!emptyM)
                                state <= S_PROC_MSG;
                            else begin
                                tag_out <= gift_out;
                                state   <= S_DONE;
                            end
                        end else begin
                            remaining_ad <= remaining_ad - 8'd16;
                            state        <= S_REQ_AD;
                        end
                    end
                end

                // =================================================
                // S_REQ_AD
                // =================================================
                S_REQ_AD: begin
                    ad_req <= 1'b1;
                    if (ad_ack)
                        state <= S_PROC_AD;
                end

                // =================================================
                // S_PROC_MSG
                // =================================================
                S_PROC_MSG: begin
                    is_last_msg <= last_msg_now;

                    if (!last_msg_now) begin
                        L <= L_dbl;
                    end else begin
                        if (!partial_msg) L <= L_tri;
                        else              L <= L_tri2;
                    end

                    data_out       <= msg_xor_out;
                    data_out_valid <= 1'b1;
                    gift_in        <= msg_pho1_X;

                    gift_start <= 1'b1;
                    state      <= S_WAIT_MSG;
                end

                // =================================================
                // S_WAIT_MSG
                // =================================================
                S_WAIT_MSG: begin
                    if (gift_done) begin
                        Y_prev <= gift_out;

                        if (is_last_msg) begin
                            tag_out <= gift_out;
                            state   <= S_DONE;
                        end else begin
                            remaining_msg <= remaining_msg - 8'd16;
                            state         <= S_REQ_MSG;
                        end
                    end
                end

                // =================================================
                // S_REQ_MSG
                // =================================================
                S_REQ_MSG: begin
                    msg_req <= 1'b1;
                    if (msg_ack)
                        state <= S_PROC_MSG;
                end

                // =================================================
                // S_DONE
                // =================================================
                S_DONE: begin
                    done <= 1'b1;
                    if (decrypt_mode)
                        valid <= (tag_out == tag_in);
                    else
                        valid <= 1'b1;

                    if (!start)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
