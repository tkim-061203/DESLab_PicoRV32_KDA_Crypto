// ============================================================
// axi_to_apb_bridge.v
// AXI4-Lite slave → APB master bridge
//
// APB spec: AMBA APB Protocol v2.0 (IHI0024C)
//   IDLE  : PSEL=0  PENABLE=0
//   SETUP : PSEL=1  PENABLE=0  (1 cycle)
//   ACCESS: PSEL=1  PENABLE=1  (until PREADY=1)
//
// Latency: 2 cycles when PREADY=1 (zero-wait-state slaves)
//          N+2 cycles when slave inserts N wait states
// Write priority over read.
// ============================================================

module axi_to_apb_bridge (
    input         clk,
    input         resetn,

    // --------------------------------------------------------
    // AXI4-Lite slave (from CPU / AXI interconnect)
    // --------------------------------------------------------
    input         s_awvalid,
    output        s_awready,
    input  [31:0] s_awaddr,

    input         s_wvalid,
    output        s_wready,
    input  [31:0] s_wdata,
    input  [ 3:0] s_wstrb,

    output reg    s_bvalid,
    input         s_bready,

    input         s_arvalid,
    output        s_arready,
    input  [31:0] s_araddr,

    output reg    s_rvalid,
    input         s_rready,
    output [31:0] s_rdata,

    // --------------------------------------------------------
    // APB master (to APB interconnect / peripheral bus)
    // --------------------------------------------------------
    output        PCLK,      // pass-through of clk
    output        PRESETn,   // pass-through of resetn

    output [31:0] PADDR,
    output        PSEL,
    output        PENABLE,
    output        PWRITE,
    output [31:0] PWDATA,
    output [ 3:0] PSTRB,     // byte enable: valid on writes, 0 on reads

    input  [31:0] PRDATA,    // from APB interconnect PRDATA mux
    input         PREADY,    // from APB interconnect PREADY mux
                             // (tie 1'b1 for all zero-wait-state slaves)
    input         PSLVERR    // from APB interconnect (tie 1'b0 if unused)
);

    // --------------------------------------------------------
    // Clock / reset pass-through to APB bus
    // --------------------------------------------------------
    assign PCLK    = clk;
    assign PRESETn = resetn;

    // --------------------------------------------------------
    // State machine
    // --------------------------------------------------------
    localparam IDLE   = 2'd0;
    localparam SETUP  = 2'd1;
    localparam ACCESS = 2'd2;

    reg [1:0]  state;
    reg        apb_psel_r, apb_penable_r, apb_pwrite_r;
    /* synthesis max_fanout = 16 */
    reg [31:0] apb_paddr_r, apb_pwdata_r;
    reg [ 3:0] apb_pstrb_r;
    reg [31:0] rdata_r;

    // --------------------------------------------------------
    // Handshake conditions
    //   Write: need both AW and W channels valid simultaneously
    //   Read : only AR channel, lower priority than write
    // --------------------------------------------------------
    wire aw_acc = (state == IDLE) && s_awvalid && s_wvalid && !s_bvalid;
    wire ar_acc = (state == IDLE) && s_arvalid && !s_rvalid && !aw_acc;

    assign s_awready = aw_acc;
    assign s_wready  = aw_acc;
    assign s_arready = ar_acc;
    assign s_rdata   = rdata_r;

    // --------------------------------------------------------
    // APB outputs (registered)
    // --------------------------------------------------------
    assign PADDR   = apb_paddr_r;
    assign PSEL    = apb_psel_r;
    assign PENABLE = apb_penable_r;
    assign PWRITE  = apb_pwrite_r;
    assign PWDATA  = apb_pwdata_r;
    assign PSTRB   = apb_pstrb_r;

    // --------------------------------------------------------
    // FSM
    // --------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            state         <= IDLE;
            apb_psel_r    <= 1'b0;
            apb_penable_r <= 1'b0;
            apb_pwrite_r  <= 1'b0;
            apb_paddr_r   <= 32'h0;
            apb_pwdata_r  <= 32'h0;
            apb_pstrb_r   <= 4'h0;
            s_bvalid      <= 1'b0;
            s_rvalid      <= 1'b0;
            rdata_r       <= 32'h0;
        end else begin

            // Clear responses once CPU acknowledges
            if (s_bvalid && s_bready) s_bvalid <= 1'b0;
            if (s_rvalid && s_rready) s_rvalid <= 1'b0;

            case (state)

                // ----------------------------------------
                // IDLE: latch request, move to SETUP
                // ----------------------------------------
                IDLE: begin
                    if (aw_acc) begin               // write has priority
                        apb_psel_r    <= 1'b1;
                        apb_penable_r <= 1'b0;      // SETUP phase starts
                        apb_pwrite_r  <= 1'b1;
                        apb_paddr_r   <= s_awaddr;
                        apb_pwdata_r  <= s_wdata;
                        apb_pstrb_r   <= s_wstrb;
                        state         <= SETUP;
                    end else if (ar_acc) begin
                        apb_psel_r    <= 1'b1;
                        apb_penable_r <= 1'b0;      // SETUP phase starts
                        apb_pwrite_r  <= 1'b0;
                        apb_paddr_r   <= s_araddr;
                        apb_pwdata_r  <= 32'h0;
                        apb_pstrb_r   <= 4'b0000;   // spec: PSTRB=0 on reads
                        state         <= SETUP;
                    end
                end

                // ----------------------------------------
                // SETUP: PSEL=1, PENABLE=0 for 1 cycle
                // ----------------------------------------
                SETUP: begin
                    apb_penable_r <= 1'b1;          // access phase starts
                    state         <= ACCESS;
                end

                // ----------------------------------------
                // ACCESS: PSEL=1, PENABLE=1
                // Hold all APB signals stable until PREADY=1
                // (spec §3.1.2 — slave may insert wait states)
                // ----------------------------------------
                ACCESS: begin
                    if (PREADY) begin
                        apb_psel_r    <= 1'b0;
                        apb_penable_r <= 1'b0;

                        if (apb_pwrite_r) begin
                            // Write: return write response to AXI
                            // PSLVERR could map to s_bresp[1] — ignored here
                            s_bvalid <= 1'b1;
                        end else begin
                            // Read: latch data, return to AXI
                            rdata_r  <= PRDATA;
                            s_rvalid <= 1'b1;
                        end
                        state <= IDLE;
                    end
                    // else: hold — slave is inserting wait states
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

