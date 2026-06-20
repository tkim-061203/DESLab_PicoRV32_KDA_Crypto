// ============================================================
// GIFT-128 SubCells 
// ============================================================
module gift128_subcells (
    input  wire [31:0] S0,
    input  wire [31:0] S1,
    input  wire [31:0] S2,
    input  wire [31:0] S3,
    output reg  [31:0] Z0,
    output reg  [31:0] Z1,
    output reg  [31:0] Z2,
    output reg  [31:0] Z3
);

    reg [31:0] s1_0, s1_1;
    reg [31:0] s2_1, s2_2, s2_3;

    always @(*) begin
        // --- Stage 1: nonlinear mix ---
        s1_1 = S1 ^ (S0 & S2);
        s1_0 = S0 ^ (s1_1 & S3);

        // --- Stage 2: dependency propagation ---
        s2_2 = S2 ^ (S0 | S1);
        s2_3 = S3 ^ s2_2;
        s2_1 = s1_1 ^ s2_3;

        // --- Stage 3 & swap S0<->S3 ---
        Z0 = ~s2_3;
        Z1 = s2_1;
        Z2 = s2_2 ^ (s1_0 & s2_1);
        Z3 = s1_0;
    end

endmodule

