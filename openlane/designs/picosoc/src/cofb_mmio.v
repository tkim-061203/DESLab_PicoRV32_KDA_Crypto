`default_nettype none
`timescale 1ns / 1ps

module cofb_mmio (
`ifdef USE_POWER_PINS
    inout  wire         VPWR,
    inout  wire         VGND,
`endif
    input  wire         clk,
    input  wire         rst_n,
    input  wire         wr_en,
    input  wire [7:0]   reg_addr,
    input  wire [31:0]  reg_wdata,
    output reg  [31:0]  reg_rdata
);
    reg [127:0] key_reg;
    reg [127:0] nonce_reg;
    reg [127:0] ad_reg;
    reg [127:0] data_in_reg;
    reg [127:0] tag_in_reg;
    reg [7:0]   ad_length_reg;
    reg [7:0]   data_length_reg;
    reg         decrypt_mode_reg;
    reg         start_pulse;
    reg         ad_ack_pulse;
    reg         msg_ack_pulse;
    reg         done_sticky;
    reg         valid_sticky;

    wire [127:0] data_out;
    wire [127:0] tag_out;
    wire         valid;
    wire         done;
    wire         ad_req;
    wire         msg_req;
    wire         data_out_valid;

    cofb_core u_core (
`ifdef USE_POWER_PINS
        .VPWR(VPWR),
        .VGND(VGND),
`endif
        .clk(clk),
        .rst_n(rst_n),
        .start(start_pulse),
        .decrypt_mode(decrypt_mode_reg),
        .key(key_reg),
        .nonce(nonce_reg),
        .ad_data(ad_reg),
        .ad_total_len(ad_length_reg),
        .ad_ack(ad_ack_pulse),
        .msg_data(data_in_reg),
        .msg_total_len(data_length_reg),
        .msg_ack(msg_ack_pulse),
        .tag_in(tag_in_reg),
        .ad_req(ad_req),
        .msg_req(msg_req),
        .data_out(data_out),
        .data_out_valid(data_out_valid),
        .tag_out(tag_out),
        .valid(valid),
        .done(done)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            key_reg          <= '0;
            nonce_reg        <= '0;
            ad_reg           <= '0;
            data_in_reg      <= '0;
            tag_in_reg       <= '0;
            ad_length_reg    <= '0;
            data_length_reg  <= '0;
            decrypt_mode_reg <= 1'b0;
            start_pulse      <= 1'b0;
            ad_ack_pulse     <= 1'b0;
            msg_ack_pulse    <= 1'b0;
            done_sticky      <= 1'b0;
            valid_sticky     <= 1'b0;
        end else begin
            start_pulse   <= 1'b0;
            ad_ack_pulse  <= 1'b0;
            msg_ack_pulse <= 1'b0;

            if (start_pulse) begin
                done_sticky  <= 1'b0;
                valid_sticky <= 1'b0;
            end else if (done) begin
                done_sticky  <= 1'b1;
                valid_sticky <= valid;
            end

            if (wr_en) begin
                case (reg_addr)
                    8'h00: key_reg[31:0]       <= reg_wdata;
                    8'h04: key_reg[63:32]      <= reg_wdata;
                    8'h08: key_reg[95:64]      <= reg_wdata;
                    8'h0C: key_reg[127:96]     <= reg_wdata;
                    8'h10: nonce_reg[31:0]     <= reg_wdata;
                    8'h14: nonce_reg[63:32]    <= reg_wdata;
                    8'h18: nonce_reg[95:64]    <= reg_wdata;
                    8'h1C: nonce_reg[127:96]   <= reg_wdata;
                    8'h20: ad_reg[31:0]        <= reg_wdata;
                    8'h24: ad_reg[63:32]       <= reg_wdata;
                    8'h28: ad_reg[95:64]       <= reg_wdata;
                    8'h2C: ad_reg[127:96]      <= reg_wdata;
                    8'h30: data_in_reg[31:0]   <= reg_wdata;
                    8'h34: data_in_reg[63:32]  <= reg_wdata;
                    8'h38: data_in_reg[95:64]  <= reg_wdata;
                    8'h3C: data_in_reg[127:96] <= reg_wdata;
                    8'h40: tag_in_reg[31:0]    <= reg_wdata;
                    8'h44: tag_in_reg[63:32]   <= reg_wdata;
                    8'h48: tag_in_reg[95:64]   <= reg_wdata;
                    8'h4C: tag_in_reg[127:96]  <= reg_wdata;
                    8'h50: begin
                        decrypt_mode_reg <= reg_wdata[16];
                        ad_length_reg    <= reg_wdata[15:8];
                        data_length_reg  <= reg_wdata[7:0];
                        start_pulse      <= 1'b1;
                    end
                    8'h78: begin
                        ad_ack_pulse  <= reg_wdata[1];
                        msg_ack_pulse <= reg_wdata[0];
                    end
                    default: ;
                endcase
            end
        end
    end

    always @* begin
        case (reg_addr)
            8'h54:   reg_rdata = {27'd0, data_out_valid, ad_req, msg_req,
                                  done_sticky, valid_sticky};
            8'h58:   reg_rdata = data_out[31:0];
            8'h5C:   reg_rdata = data_out[63:32];
            8'h60:   reg_rdata = data_out[95:64];
            8'h64:   reg_rdata = data_out[127:96];
            8'h68:   reg_rdata = tag_out[31:0];
            8'h6C:   reg_rdata = tag_out[63:32];
            8'h70:   reg_rdata = tag_out[95:64];
            8'h74:   reg_rdata = tag_out[127:96];
            default: reg_rdata = 32'h0;
        endcase
    end
endmodule

