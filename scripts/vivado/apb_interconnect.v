// ============================================================
// apb_interconnect.v
// APB address decoder + PRDATA/PREADY mux
//
// 7 slaves, decoded on PADDR[31:28]:
//   0x0xxx_xxxx → PSEL_rom    (Boot ROM)
//   0x1xxx_xxxx → PSEL_uart   (UART + LED)
//   0x2xxx_xxxx → PSEL_input  (SW / BTN)
//   0x3xxx_xxxx → PSEL_jambu  (TinyJAMBU)
//   0x4xxx_xxxx → PSEL_xdy    (Xoodyak)
//   0x5xxx_xxxx → PSEL_cofb   (GIFT-COFB)
//   0x6xxx_xxxx → PSEL_sdspi  (SD SPI)
//
// All signals are purely combinational (no registers).
// Tie PREADY_* = 1'b1 and PSLVERR_* = 1'b0 for
// zero-wait-state, error-free slaves.
// ============================================================

module apb_interconnect (
    // --------------------------------------------------------
    // APB master signals (from axi_to_apb_bridge)
    // --------------------------------------------------------
    input  [31:0] PADDR,
    input         PSEL,         // master PSEL (bridge drives high when active)
    input         PENABLE,      // forwarded to all slaves
    input         PWRITE,       // forwarded to all slaves
    input  [31:0] PWDATA,       // forwarded to all slaves
    input  [ 3:0] PSTRB,        // forwarded to all slaves

    // --------------------------------------------------------
    // PSELx outputs — one per slave
    // --------------------------------------------------------
    output        PSEL_rom,
    output        PSEL_uart,
    output        PSEL_input,
    output        PSEL_jambu,
    output        PSEL_xdy,
    output        PSEL_cofb,
    output        PSEL_sdspi,

    // --------------------------------------------------------
    // PRDATA from each slave (muxed back to bridge)
    // --------------------------------------------------------
    input  [31:0] PRDATA_rom,
    input  [31:0] PRDATA_uart,
    input  [31:0] PRDATA_input,
    input  [31:0] PRDATA_jambu,
    input  [31:0] PRDATA_xdy,
    input  [31:0] PRDATA_cofb,
    input  [31:0] PRDATA_sdspi,

    // --------------------------------------------------------
    // PREADY from each slave
    // (tie 1'b1 if slave has no wait states)
    // --------------------------------------------------------
    input         PREADY_rom,
    input         PREADY_uart,
    input         PREADY_input,
    input         PREADY_jambu,
    input         PREADY_xdy,
    input         PREADY_cofb,
    input         PREADY_sdspi,

    // --------------------------------------------------------
    // PSLVERR from each slave
    // (tie 1'b0 if slave never generates errors)
    // --------------------------------------------------------
    input         PSLVERR_rom,
    input         PSLVERR_uart,
    input         PSLVERR_input,
    input         PSLVERR_jambu,
    input         PSLVERR_xdy,
    input         PSLVERR_cofb,
    input         PSLVERR_sdspi,

    // --------------------------------------------------------
    // Muxed outputs back to bridge
    // --------------------------------------------------------
    output [31:0] PRDATA,
    output        PREADY,
    output        PSLVERR
);

    // --------------------------------------------------------
    // Address decode — top 4 bits select slave
    // --------------------------------------------------------
    wire [3:0] region = PADDR[31:28];

    assign PSEL_rom   = PSEL && (region == 4'h0);
    assign PSEL_uart  = PSEL && (region == 4'h1);
    assign PSEL_input = PSEL && (region == 4'h2);
    assign PSEL_jambu = PSEL && (region == 4'h3);
    assign PSEL_xdy   = PSEL && (region == 4'h4);
    assign PSEL_cofb  = PSEL && (region == 4'h5);
    assign PSEL_sdspi = PSEL && (region == 4'h6);

    // --------------------------------------------------------
    // PRDATA mux — only selected slave drives the bus
    // --------------------------------------------------------
    assign PRDATA =
        PSEL_rom   ? PRDATA_rom   :
        PSEL_uart  ? PRDATA_uart  :
        PSEL_input ? PRDATA_input :
        PSEL_jambu ? PRDATA_jambu :
        PSEL_xdy   ? PRDATA_xdy   :
        PSEL_cofb  ? PRDATA_cofb  :
        PSEL_sdspi ? PRDATA_sdspi :
        32'h0;

    // --------------------------------------------------------
    // PREADY mux — default 1 when no slave is selected
    // --------------------------------------------------------
    assign PREADY =
        PSEL_rom   ? PREADY_rom   :
        PSEL_uart  ? PREADY_uart  :
        PSEL_input ? PREADY_input :
        PSEL_jambu ? PREADY_jambu :
        PSEL_xdy   ? PREADY_xdy   :
        PSEL_cofb  ? PREADY_cofb  :
        PSEL_sdspi ? PREADY_sdspi :
        1'b1;  // no slave selected → always ready

    // --------------------------------------------------------
    // PSLVERR mux — default 0 (no error) if no slave selected
    // --------------------------------------------------------
    assign PSLVERR =
        PSEL_rom   ? PSLVERR_rom   :
        PSEL_uart  ? PSLVERR_uart  :
        PSEL_input ? PSLVERR_input :
        PSEL_jambu ? PSLVERR_jambu :
        PSEL_xdy   ? PSLVERR_xdy   :
        PSEL_cofb  ? PSLVERR_cofb  :
        PSEL_sdspi ? PSLVERR_sdspi :
        1'b0;

endmodule

