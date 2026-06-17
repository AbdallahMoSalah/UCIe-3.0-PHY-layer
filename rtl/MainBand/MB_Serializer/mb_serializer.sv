`timescale 1ps/1ps
// =============================================================================
// Module  : MB_SERIALIZER
// Project : UCIe 3.0 Main-Band Physical Layer
// Purpose : True DDR parallel-to-serial converter.
//           - Accepts DATA_WIDTH-bit word on mb_clk domain (Ser_en pulse)
//           - Serialises LSB-first at PLL_clk rate: 2 bits per PLL cycle
//             (posedge → even bit, negedge → odd bit)
//           - DATA_WIDTH=32 → 16 PLL cycles per flit word
//           - mb_clk:PLL_clk ratio = 1:16  (DDR gives effective 1:32)
//
// CDC : 3-FF toggle synchroniser  mb_clk → PLL_clk.
// DDR : pos_out driven at posedge, neg_out driven at posedge but
//       held for the subsequent half-cycle — SER_out MUX selects
//       PLL_clk ? pos_out : neg_out.
// =============================================================================

module MB_SERIALIZER #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   mb_clk,
    input  wire                   PLL_clk,
    input  wire                   i_rst_n,
    input  wire                   Ser_en,
    input  wire [DATA_WIDTH-1:0]  in_data,
    output wire                   SER_out
);

    // =========================================================================
    // Local constants
    // =========================================================================
    localparam int HALF = DATA_WIDTH / 2;   // 16 posedge cycles per word

    // =========================================================================
    // mb_clk domain : latch in_data whenever Ser_en is asserted
    // =========================================================================
    reg [DATA_WIDTH-1:0] load_reg;
    reg                  load_toggle_mb;

    always @(posedge mb_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            load_reg       <= {DATA_WIDTH{1'b0}};
            load_toggle_mb <= 1'b0;
        end else if (Ser_en) begin
            load_reg       <= in_data;
            load_toggle_mb <= ~load_toggle_mb; // toggle on every load
        end
    end

    // =========================================================================
    // CDC : 3-FF toggle synchroniser  (mb_clk → PLL_clk)
    // =========================================================================
    reg sync1_toggle, sync2_toggle, sync3_toggle;

    always @(posedge PLL_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            sync1_toggle <= 1'b0;
            sync2_toggle <= 1'b0;
            sync3_toggle <= 1'b0;
        end else begin
            sync1_toggle <= load_toggle_mb;   // capture
            sync2_toggle <= sync1_toggle;     // sync
            sync3_toggle <= sync2_toggle;     // edge detect
        end
    end

    // 1-cycle PLL_clk pulse on any toggle edge (new word available)
    wire load_pulse = (sync2_toggle != sync3_toggle);

    // =========================================================================
    // PLL_clk domain : true DDR shift register
    //
    //   Each posedge:
    //     1. Capture current shift_reg[0] → pos_out (drives SER_out HIGH phase)
    //     2. Capture current shift_reg[1] → neg_out (drives SER_out LOW  phase)
    //     3. Shift shift_reg right by 2 bits.
    //
    //   SER_out MUX (combinational):
    //     PLL_clk = 1  →  pos_out  (set at last posedge)
    //     PLL_clk = 0  →  neg_out  (set at last posedge, stable through negedge)
    //
    //   16 posedge cycles transmit all 32 bits, LSB first.
    // =========================================================================
    reg [DATA_WIDTH-1:0] shift_reg;
    reg [4:0]            ser_cnt;    // 0 = idle/done; 1..HALF-1 = active
    reg                  pos_out;    // even-bit output (SER high phase)
    reg                  neg_out;    // odd-bit  output (SER low  phase)

    always @(posedge PLL_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            shift_reg <= {DATA_WIDTH{1'b0}};
            ser_cnt   <= 5'd0;
            pos_out   <= 1'b0;
            neg_out   <= 1'b0;
        end else begin
            if (load_pulse) begin
                // ── First cycle: output bits [1:0] of the new word ──────────
                pos_out   <= load_reg[0];                        // bit 0 on posedge
                neg_out   <= load_reg[1];                        // bit 1 on negedge
                shift_reg <= {2'b00, load_reg[DATA_WIDTH-1:2]}; // pre-shift
                ser_cnt   <= 5'd1;
            end else if (ser_cnt > 5'd0 && ser_cnt < HALF[4:0]) begin
                // ── Cycles 1 .. HALF-1 ──────────────────────────────────────
                pos_out   <= shift_reg[0];
                neg_out   <= shift_reg[1];
                shift_reg <= {2'b00, shift_reg[DATA_WIDTH-1:2]};
                ser_cnt   <= ser_cnt + 5'd1;
            end else begin
                // ── Idle or done ─────────────────────────────────────────────
                pos_out <= 1'b0;
                neg_out <= 1'b0;
                ser_cnt <= 5'd0;
            end
        end
    end

    // DDR output MUX — combinational, no glitch between posedge and negedge
    assign #10 SER_out = PLL_clk ? pos_out : neg_out;

endmodule
