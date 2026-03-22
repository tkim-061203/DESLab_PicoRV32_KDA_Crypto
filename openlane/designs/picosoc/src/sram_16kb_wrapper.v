`default_nettype none
// ============================================================
// sram_16kb_wrapper
//   Drop-in replacement for sky130_sram_16kbyte_1rw1r_32x4096_8
//   using 4 × sky130_sram_4kbyte_1rw1r_32x1024_8 instances
//   with 2-bit bank-select from addr[11:10].
//
//   Port interface is identical to the 16 kB macro.
// ============================================================
module sram_16kb_wrapper (
`ifdef USE_POWER_PINS
    inout vccd1,
    inout vssd1,
`endif
    input  wire        clk0,
    input  wire        csb0,
    input  wire        web0,
    input  wire [3:0]  wmask0,
    input  wire [11:0] addr0,
    input  wire [31:0] din0,
    output wire [31:0] dout0,
    input  wire        clk1,
    input  wire        csb1,
    input  wire [11:0] addr1,
    output wire [31:0] dout1
);

    // Bank select from 2 MSBs of address
    wire [1:0] bank_sel0 = addr0[11:10];
    wire [1:0] bank_sel1 = addr1[11:10];

    // Per-bank chip-select (active-low): assert only when
    // the master csb is low AND this bank is addressed.
    wire [3:0] csb0_bank;
    wire [3:0] csb1_bank;
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_cs
            assign csb0_bank[i] = csb0 | (bank_sel0 != i[1:0]);
            assign csb1_bank[i] = csb1 | (bank_sel1 != i[1:0]);
        end
    endgenerate

    // Data outputs from each bank
    wire [31:0] dout0_bank [0:3];
    wire [31:0] dout1_bank [0:3];

    // Instantiate 4 × 4 kB SRAM banks
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_bank
            sky130_sram_4kbyte_1rw1r_32x1024_8 u_bank (
            `ifdef USE_POWER_PINS
                .vccd1 (vccd1),
                .vssd1 (vssd1),
            `endif
                .clk0  (clk0),
                .csb0  (csb0_bank[i]),
                .web0  (web0),
                .wmask0(wmask0),
                .addr0 (addr0[9:0]),      // 10-bit word address within bank
                .din0  (din0),
                .dout0 (dout0_bank[i]),
                .clk1  (clk1),
                .csb1  (csb1_bank[i]),
                .addr1 (addr1[9:0]),
                .dout1 (dout1_bank[i])
            );
        end
    endgenerate

    // --------------------------------------------------------
    // Read mux – register the bank select (SRAM output is
    // synchronous, so data appears one cycle after address).
    // --------------------------------------------------------
    reg [1:0] bank_sel0_r, bank_sel1_r;

    always @(posedge clk0)
        if (!csb0) bank_sel0_r <= bank_sel0;

    always @(posedge clk1)
        if (!csb1) bank_sel1_r <= bank_sel1;

    assign dout0 = dout0_bank[bank_sel0_r];
    assign dout1 = dout1_bank[bank_sel1_r];

endmodule
