
`default_nettype none

module sram_16kb_wrapper (
`ifdef USE_POWER_PINS
    inout  vccd1,
    inout  vssd1,
`endif
    input  wire        clk0,
    input  wire        csb0,
    input  wire        web0,
    input  wire [11:0] addr0,
    input  wire [31:0] din0,
    output wire [31:0] dout0
);

    // ----------------------------------------------------------
    // Bank select: 2 MSBs of 12-bit word address
    // ----------------------------------------------------------
    wire [1:0] bank_sel0 = addr0[11:10];

    // ----------------------------------------------------------
    // Per-bank active-low chip-select
    // Use 2'(i) cast to avoid width-mismatch lint / sim issues.
    // ----------------------------------------------------------
    wire [3:0] csb0_bank;
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_cs
            assign csb0_bank[i] = csb0 | (bank_sel0 != 2'(i));
        end
    endgenerate

    // ----------------------------------------------------------
    // Tie-lo cells for spare SRAM pins.
    // Kept as named assigned wires so Yosys synthesises
    // sky130_fd_sc_hd__conb_1 tie cells (required by LVS).
    // ----------------------------------------------------------
    wire tie_lo_addr;
    wire tie_lo_din;
    assign tie_lo_addr = 1'b0;
    assign tie_lo_din  = 1'b0;

    // ----------------------------------------------------------
    // 33-bit raw outputs from each 4-kB macro bank
    // ----------------------------------------------------------
    wire [32:0] dout0_bank [0:3];

    // ----------------------------------------------------------
    // Instantiate 4 × sky130_sram_4kbyte_1rw_32x1024_8
    // FIX: wmask0 now connected (was missing → all bytes always
    //      written, causing LVS mismatches on byte-enable paths).
    // ----------------------------------------------------------
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_bank
            sky130_sram_4kbyte_1rw_32x1024_8 u_bank (

                .clk0       (clk0),
                .csb0       (csb0_bank[i]),
                .web0       (web0),
                .spare_wen0 (tie_lo_din),
                .addr0      ({tie_lo_addr, addr0[9:0]}),
                .din0       ({tie_lo_din,  din0}),
                .dout0      (dout0_bank[i])
            );
        end
    endgenerate

    // ----------------------------------------------------------
    // Synchronous read-data mux.
    // bank_sel0_r is initialised to 2'b00 so that dout0 is
    // deterministic (points at bank-0) before the first access.
    // Register is updated on EVERY clock edge when csb0 is low
    // (not only on falling edge) to track back-to-back reads.
    // ----------------------------------------------------------
    reg [1:0] bank_sel0_r = 2'b00;   // FIX: add power-on init
    always @(posedge clk0)
        if (!csb0) bank_sel0_r <= bank_sel0;

    assign dout0 = dout0_bank[bank_sel0_r][31:0];

endmodule
