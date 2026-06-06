`timescale 1ns/1ps
// =============================================================================
// Module : MB_DESERIALIZER_VALID   (Option-A FRAMING MASTER — lives in unsued/)
// =============================================================================
// Valid-lane DDR deserializer + framer for the whole MainBand RX.
//
// The valid lane carries the canonical pattern 0x0F0F0F0F (unsued/Valid_tx.sv),
// which serializes LSB-first as 1,1,1,1,0,0,0,0 per byte. So the *posedge* of
// the received serial valid (RVLD_P) lands exactly on the byte/word boundary.
// This block locks onto the FIRST such posedge after ser_valid_en, then free-
// runs a /16 pair counter and broadcasts two pll_clk strobes so EVERY data lane
// captures on the valid-frame boundary instead of guessing from enable timing:
//
//   o_frame_start : 1-cycle lock pulse (first valid posedge after enable).
//   o_word_load   : HIGH during the pll cycle whose NEGEDGE captures the last
//                   (16th) pair of a word. It is registered on the POSEDGE so it
//                   is stable when the negedge-clocked data lanes sample it
//                   -> no cross-module delta race.
//
// DDR pairing is the fixed (negedge same-cycle) scheme from unsued/
// mb_deserializer.sv: at negedge n, r_data_pos = word[2n] (this cycle's posedge
// capture) and ser_data_in = word[2n+1] (live LOW phase).
//
// Lock alignment: the valid posedge physically occurs in cycle c0; the posedge
// edge-detector (registered) reports it one cycle later (c0+1), at which point
// pair0 has already been captured on the c0 negedge. Presetting the counter to
// LOCK_PRESET = 2 there makes o_word_load fire on the negedge that captures
// pair15 -> the latched word is byte/bit aligned to the transmitted frame.
// (Verified against RVLD_L == 0x0F0F0F0F and the data lockstep checker.)
// =============================================================================
module MB_DESERIALIZER_VALID #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   MB_clk,
    input  wire                   pll_clk,
    input  wire                   i_rst_n,
    input  wire                   ser_valid_en,
    input  wire                   ser_data_in,            // = RVLD_P (serial valid)
    output reg                    enable_des_valid_frame,
    output reg  [DATA_WIDTH-1:0]  par_data_out,           // = RVLD_L (parallel valid)
    output reg                    de_ser_done,
    // ---- framing strobes to the 16 data-lane deserializers (pll_clk domain) ----
    output reg                    o_word_load,
    output reg                    o_frame_start
);

    localparam [5:0] TERM        = (DATA_WIDTH/2) - 1;    // 15 : last pair index
    localparam [5:0] LOCK_PRESET = 6'd2;                  // counter preset at lock

    /* -------------------------------------------------- */
    /* Internal registers                                 */
    /* -------------------------------------------------- */
    reg [DATA_WIDTH-1:0] shift_reg;
    reg [DATA_WIDTH-1:0] save_data;

    // CDC handshake (pll_clk -> MB_clk)
    reg save_data_toggle;
    reg sync1_toggle, sync2_toggle, sync3_toggle;
    wire valid_pulse;

    // Framer state (pll_clk / posedge domain)
    reg        r_data_pos;       // even bit, captured on rising edge (word[2n])
    reg        r_data_pos_d;     // 1-cycle delay for posedge detect
    reg        locked;
    reg [5:0]  pair_cnt;
    wire       val_pos_rise = r_data_pos & ~r_data_pos_d;

    /* -------------------------------------------------- */
    /* DDR even-bit capture (rising edge)                 */
    /* -------------------------------------------------- */
    always @(posedge pll_clk or negedge i_rst_n) begin
        if (!i_rst_n) r_data_pos <= 1'b0;
        else if (ser_valid_en) r_data_pos <= ser_data_in;   // word[2n] (HIGH phase)
    end

    /* -------------------------------------------------- */
    /* Framer: edge-detect, lock-once, /16 counter        */
    /* -------------------------------------------------- */
    always @(posedge pll_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_data_pos_d  <= 1'b0;
            locked        <= 1'b0;
            pair_cnt      <= 6'd0;
            o_word_load   <= 1'b0;
            o_frame_start <= 1'b0;
        end else begin
            r_data_pos_d  <= r_data_pos;
            o_frame_start <= 1'b0;          // default: 1-cycle pulse
            if (ser_valid_en) begin
                if (!locked) begin
                    o_word_load <= 1'b0;
                    if (val_pos_rise) begin
                        locked        <= 1'b1;
                        pair_cnt      <= LOCK_PRESET;
                        o_frame_start <= 1'b1;     // lock pulse
                    end
                end else begin
                    if (pair_cnt == TERM) begin
                        pair_cnt    <= 6'd0;
                        o_word_load <= 1'b1;       // HIGH for this cycle -> negedge latch
                    end else begin
                        pair_cnt    <= pair_cnt + 6'd1;
                        o_word_load <= 1'b0;
                    end
                end
            end else begin
                locked      <= 1'b0;
                pair_cnt    <= 6'd0;
                o_word_load <= 1'b0;
            end
        end
    end

    /* -------------------------------------------------- */
    /* Shift + framed latch on negedge (same-cycle pair)  */
    /* -------------------------------------------------- */
    always @(negedge pll_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            shift_reg        <= {DATA_WIDTH{1'b0}};
            save_data        <= {DATA_WIDTH{1'b0}};
            save_data_toggle <= 1'b0;
        end else if (ser_valid_en) begin
            shift_reg <= {ser_data_in, r_data_pos, shift_reg[DATA_WIDTH-1:2]};
            if (o_word_load) begin
                save_data        <= {ser_data_in, r_data_pos, shift_reg[DATA_WIDTH-1:2]};
                save_data_toggle <= ~save_data_toggle;
            end
        end
    end

    /* -------------------------------------------------- */
    /* CDC pll_clk -> MB_clk (toggle synchronizer)        */
    /* -------------------------------------------------- */
    always @(posedge MB_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            sync1_toggle <= 1'b0;
            sync2_toggle <= 1'b0;
            sync3_toggle <= 1'b0;
        end else begin
            sync1_toggle <= save_data_toggle;
            sync2_toggle <= sync1_toggle;
            sync3_toggle <= sync2_toggle;
        end
    end
    assign valid_pulse = (sync2_toggle != sync3_toggle);

    /* -------------------------------------------------- */
    /* Output + valid-frame enable (MB_clk domain)        */
    /* -------------------------------------------------- */
    always @(posedge MB_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            par_data_out           <= {DATA_WIDTH{1'b0}};
            de_ser_done            <= 1'b0;
            enable_des_valid_frame <= 1'b0;
        end else begin
            de_ser_done <= 1'b0;            // default off (1-cycle pulse)
            if (valid_pulse) begin
                par_data_out           <= save_data;
                de_ser_done            <= 1'b1;
                enable_des_valid_frame <= (save_data != {DATA_WIDTH{1'b0}});
            end
        end
    end

endmodule
