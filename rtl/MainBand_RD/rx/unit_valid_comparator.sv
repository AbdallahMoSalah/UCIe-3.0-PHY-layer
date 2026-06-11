// Module: VALID_COMPARATOR
// Status: WIP
// Description:
//   UCIe 3.0 MainBand RX comparator for the single Valid Lane.
//   It is the Valid-Lane counterpart of unit_mb_pattern_comparator, but for
//   ONE Lane only: there is no Lane array and no Lane mask.
//
//   The expected pattern is the fixed Valid-frame byte (00001111 = 0x0F)
//   repeated across the word, i.e. the 32-bit word 0x0F0F0F0F that the TX
//   Valid path drives on o_TVLD_L.
//
//   Two comparison schemes are selected by i_mode:
//       1 = Bit-error threshold  (like the LFSR mode of the pattern comparator)
//             Every received bit is XORed against the expected pattern, the
//             mismatched bits are accumulated, and at the end of the test the
//             Lane PASSes if the accumulated error count is within the
//             programmed threshold.
//       0 = 16 consecutive iterations
//             An "iteration" is one Valid-frame byte (8 bits). Each byte that
//             matches the expected byte advances a consecutive-match counter;
//             any mismatching byte resets it. Once 16 consecutive matching
//             bytes are seen the Lane PASSes (sticky) for the rest of the test.
//
//   Test length is fixed at 128 iterations (128 bytes = 1024 bits). With a
//   32-bit deserialized word that is 4 bytes/cycle => 32 clock cycles.
//
// Author: Mohamed Anwar
module unit_valid_comparator #(
    parameter int        WIDTH       = 32,            // bits per clock from the Valid deserializer
    parameter int        TOTAL_BYTES = 128,           // iterations per test (128 bytes = 1024 bits)
    parameter int        CONSEC_PASS = 16,            // consecutive matching bytes required to PASS (mode 0)
    parameter [7:0]      VALID_BYTE  = 8'b00001111    // expected Valid-frame byte (0x0F)
)(
    input  logic              i_clk,
    input  logic              i_rst_n,

    // ---------------- Control ----------------
    input  logic              i_enable,                 // run a comparison test while high
    input  logic              i_mode,                   // 0 = 16 consecutive iterations, 1 = bit-error threshold
    input  logic [15:0]       i_max_error_threshold,    // bit-error threshold (mode 1)
    input  logic              i_clear_error,

    // ---------------- Received data ----------------
    input  logic [WIDTH-1:0]  i_valid_frame_data,                // deserialized Valid-Lane word
    input  logic              i_valid_frame_vld,                // deserialized Valid-Lane word

    // ---------------- Results ----------------
    output logic              o_done,                   // test complete, result valid
    output logic              o_pass,                   // 1 = Valid Lane PASS
    output logic              o_valid_frame_error       // 1 = Valid Frame Error (when not enabled)
);
    // -------------------------------------------------------------------------
    // Derived sizes
    // -------------------------------------------------------------------------
    localparam int BYTES_PER_WORD = WIDTH / 8;              // 4 bytes per 32-bit word
    localparam int NUM_CYCLES     = TOTAL_BYTES / BYTES_PER_WORD; // 32 cycles per test

    // Expected word = Valid-frame byte replicated across the word width.
    localparam [WIDTH-1:0] EXP_WORD = {BYTES_PER_WORD{VALID_BYTE}};

    // =========================================================================
    // Popcount helper (number of set bits in a WIDTH-bit vector)
    // =========================================================================
    function automatic [15:0] popcount_w(input [WIDTH-1:0] v);
        integer i;
        begin
            popcount_w = 16'd0;
            for (i = 0; i < WIDTH; i = i + 1)
                popcount_w = popcount_w + v[i];
        end
    endfunction

    // =========================================================================
    // Per-cycle combinational mismatch evaluation
    // =========================================================================
    wire [WIDTH-1:0] mismatch = i_valid_frame_data ^ EXP_WORD;   // bitwise mismatch vs expected
    wire [15:0]      err_inc  = popcount_w(mismatch);   // mismatched bits this cycle

    // =========================================================================
    // Test FSM and accumulation
    // =========================================================================
    localparam [1:0] S_IDLE    = 2'd0,
                     S_COMPARE = 2'd1,
                     S_DONE    = 2'd2;

    reg [1:0]  state;
    reg [15:0] iter_ctr;          // 0..NUM_CYCLES-1
    reg [15:0] err_accum;         // accumulated bit errors (mode 1)
    reg [4:0]  consecutive_ctr;   // consecutive matching bytes (mode 0)

    integer b;
    always @(posedge i_clk or negedge i_rst_n) begin
        reg [4:0] temp_ctr;
        reg       temp_pass;
        if (!i_rst_n) begin
            state           <= S_IDLE;
            iter_ctr        <= 16'd0;
            err_accum       <= 16'd0;
            consecutive_ctr <= 5'd0;
            o_done          <= 1'b0;
            o_pass          <= 1'b0;
            o_valid_frame_error <= 1'b0;
        end else if (i_clear_error) begin
            state           <= S_IDLE;
            iter_ctr        <= 16'd0;
            err_accum       <= 16'd0;
            consecutive_ctr <= 5'd0;
            o_done          <= 1'b0;
            o_pass          <= 1'b0;
            o_valid_frame_error <= 1'b0;
        end else begin
            // Default value to ensure pulse behavior
            o_valid_frame_error <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    o_done <= 1'b0;
                    o_pass <= 1'b0;
                    if (i_enable) begin
                        // Start a fresh test: clear all accumulators / result.
                        iter_ctr        <= 16'd0;
                        err_accum       <= 16'd0;
                        consecutive_ctr <= 5'd0;
                        o_pass          <= 1'b0;
                        state           <= S_COMPARE;
                    end else if (i_valid_frame_vld) begin
                        if (i_valid_frame_data != EXP_WORD && i_valid_frame_data != {WIDTH{1'b0}}) begin
                            o_valid_frame_error <= 1'b1;
                        end
                    end
                end

                // ---------------------------------------------------------
                S_COMPARE: begin
                    if (!i_enable) begin
                        state <= S_IDLE;            // aborted before completion
                    end else if (i_valid_frame_vld) begin
                        if (i_mode == 1'b0) begin
                            // ---- 16 consecutive byte iterations ----
                            temp_ctr  = consecutive_ctr;
                            temp_pass = o_pass;
                            for (b = 0; b < BYTES_PER_WORD; b = b + 1) begin
                                if (i_valid_frame_data[b*8 +: 8] == VALID_BYTE) begin
                                    if (temp_ctr < CONSEC_PASS)
                                        temp_ctr = temp_ctr + 5'd1;
                                    if (temp_ctr == CONSEC_PASS)
                                        temp_pass = 1'b1;   // sticky PASS
                                end else begin
                                    temp_ctr = 5'd0;        // streak broken
                                end
                            end
                            consecutive_ctr <= temp_ctr;
                            o_pass          <= temp_pass;
                        end else begin
                            // ---- Bit-error threshold ----
                            // Accumulate mismatched bits, saturate at 16'hFFFF.
                            if (err_accum > (16'hFFFF - err_inc))
                                err_accum <= 16'hFFFF;
                            else
                                err_accum <= err_accum + err_inc;
                        end

                        // Counter and state transition
                        if (iter_ctr == NUM_CYCLES - 1)
                            state <= S_DONE;
                        else
                            iter_ctr <= iter_ctr + 16'd1;
                    end
                end

                // ---------------------------------------------------------
                S_DONE: begin
                    o_done <= 1'b1;
                    // Mode 1: PASS if accumulated bit errors are within threshold.
                    // Mode 0: o_pass is already sticky-set during S_COMPARE.
                    if (i_mode == 1'b1)
                        o_pass <= (err_accum <= i_max_error_threshold);
                    if (!i_enable)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
