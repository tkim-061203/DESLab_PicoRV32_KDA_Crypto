// ============================================================
// aead_mmap_wrapper.v
// Thin APB pass-through wrapper around crypto_cluster.
// Keeps module hierarchy: system → wrapper → cluster → cores.
// All AEAD register/mux logic lives inside crypto_cluster.
// ============================================================

module aead_mmap_wrapper (
    input  wire        clk,
    input  wire        rst_n,

    // APB slave interface (from system APB bus)
    input  wire [11:0] paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr
);

    crypto_cluster u_cluster (
        .PCLK    (clk),
        .PRESETn (rst_n),
        .PADDR   (paddr),
        .PSEL    (psel),
        .PENABLE (penable),
        .PWRITE  (pwrite),
        .PWDATA  (pwdata),
        .PRDATA  (prdata),
        .PREADY  (pready),
        .PSLVERR (pslverr)
    );

endmodule
