//--------------------------------------------------------------------------------
// Xoodoo permutation with configurable rounds per cycle
// LUT-OPTIMIZED version:
//   - Write decoder reduced to indices 0..8 (xoodyak never writes beyond 8)
//   - Read mux reduced to indices 0..3 (xoodyak never reads beyond 3)
//   - Domain XOR isolated to word 11
//   - Dead 'done' register removed
//--------------------------------------------------------------------------------

module xoodoo(
    clk_i,
    rst_i,
    start_i,
    state_valid_o,
    init_reg,
    word_in,
    word_index_in,
    word_enable_in,
    domain_i,
    domain_enable_i,
    word_out
);
    // Port declarations
    input               clk_i;
    input               rst_i;
    input               start_i;
    output reg          state_valid_o;
    input               init_reg;
    input      [31:0]   word_in;
    input      [3:0]    word_index_in;  // write: 0..8, read: 0..3 (only [1:0] used for read)
    input               word_enable_in;
    input      [31:0]   domain_i;
    input               domain_enable_i;
    output     [31:0]   word_out;

    // Parameters
    parameter roundPerCycle = 1;
    parameter active_rst    = 1'b1;

    // Internal state: 3 planes x 4 words x 32 bits = 384 bits
    reg  [383:0] reg_value;
    wire [383:0] round_out_state;

    // Round constant state machine (6 bits)
    reg  [5:0]  rc_state_in;
    wire [5:0]  rc_state_out;

    // Control signal
    reg         running;

    // =========================================================================
    // state_with_xor: apply input word + domain XOR BEFORE round computation.
    //   - Only indices 0..8 can receive word_in (xoodyak usage).
    //   - Only index 11 can receive domain_i.
    //   - Indices 9..10 pass through reg_value unchanged.
    // This removes the word_in decoder logic for 3 words and simplifies index 11.
    // =========================================================================
    wire [383:0] state_with_xor;

    genvar i;
    generate
        // Write path: indices 0..8 (covers LOAD_KEY/NONCE/AD/DATA and PAD_NONCE at idx=8)
        for (i = 0; i < 9; i = i + 1) begin : gen_word_xor_write
            assign state_with_xor[i*32 +: 32] =
                reg_value[i*32 +: 32] ^
                ((word_enable_in && (word_index_in == i[3:0])) ? word_in : 32'h0);
        end
        // Indices 9..10: no write, no domain -> pass-through
        for (i = 9; i < 11; i = i + 1) begin : gen_word_xor_passthrough
            assign state_with_xor[i*32 +: 32] = reg_value[i*32 +: 32];
        end
    endgenerate

    // Index 11: domain XOR only (no word_in path)
    assign state_with_xor[11*32 +: 32] =
        reg_value[11*32 +: 32] ^ (domain_enable_i ? domain_i : 32'h0);

    // N rounds computation module
    xoodoo_n_rounds #(.roundPerCycle(roundPerCycle)) rounds_inst(
        .state_in(state_with_xor),
        .state_out(round_out_state),
        .rc_state_in(rc_state_in),
        .rc_state_out(rc_state_out)
    );

    // =========================================================================
    // State register: combined reset paths; gated update saves dynamic power
    // =========================================================================
    always @(posedge clk_i) begin
        if (rst_i == active_rst || init_reg == 1'b1) begin
            reg_value <= 384'h0;
        end else if (running == 1'b1 || start_i == 1'b1) begin
            reg_value <= round_out_state;
        end else if (word_enable_in || domain_enable_i) begin
            // Only update if there's an actual XOR input to apply
            reg_value <= state_with_xor;
        end
        // else: hold
    end

    // =========================================================================
    // Word output: only positions 0..3 needed (xoodyak DEC absorb + tag/data/hash
    // extraction all use word_cnt_r = 0..3). 4:1 mux instead of 12:1.
    // =========================================================================
    assign word_out = reg_value[word_index_in[1:0]*32 +: 32];

    // =========================================================================
    // Main FSM controller (dead 'done' register removed)
    // =========================================================================
    always @(posedge clk_i) begin
        if (rst_i == active_rst) begin
            running       <= 1'b0;
            rc_state_in   <= 6'b011011;  // Initial RC state
            state_valid_o <= 1'b0;
        end else begin
            if (rc_state_out == 6'b010011) begin
                // Permutation complete
                running       <= 1'b0;
                rc_state_in   <= 6'b011011;
                state_valid_o <= 1'b1;
            end else if (start_i == 1'b1 || running == 1'b1) begin
                // Start or continue permutation
                running       <= 1'b1;
                rc_state_in   <= rc_state_out;
                state_valid_o <= 1'b0;
            end
            // else: hold state_valid_o (stays high after done, until next start)
        end
    end

endmodule
