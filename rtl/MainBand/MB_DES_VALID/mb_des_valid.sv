`timescale 1ns/1ps
/*****   DESERIALIZER FOR VALID LANE  ******/
// =============================================================================
// Module: MB_DESERIALIZER_VALID
// Description:
//   Edge-detection DDR deserializer for the VALID lane.
//   No external enable. Starts sampling immediately after reset.
//
//   Frame alignment FSM (pll_clk negedge domain):
//     IDLE    : waits for rising edge on ser_data_in (0→1 transition)
//               to lock onto the frame boundary.
//     RUNNING : counts 16 negedge cycles (= one complete 32-bit DDR frame).
//               At count==15, snapshots shift_reg into save_data and toggles
//               the CDC flag. If the next rising edge is detected at count==15,
//               a new frame starts immediately (back-to-back support).
//
//   CDC : 3-FF toggle synchroniser (pll_clk → MB_clk).
//
//   MB_clk domain outputs:
//     par_data_out          — the 32-bit deserialized word
//     de_ser_done           — 1-cycle pulse per new word (always fires)
//     enable_des_valid_frame — NON-STICKY: 1 when last frame == 0x0F0F0F0F,
//                              0 otherwise. Updated every frame.
// =============================================================================

module MB_DESERIALIZER_VALID #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   MB_clk,
    input  wire                   pll_clk,
    input  wire                   i_rst_n,
    input  wire                   ser_data_in,          // valid lane serial input
    output reg                    enable_des_valid_frame, // 1 when last frame == VALID_PATTERN
    output reg  [DATA_WIDTH-1:0]  par_data_out,           // latest deserialized word
    output reg                    de_ser_done             // 1-cycle pulse per new word
);

// ─────────────────────────────────────────────────────────────────────────────
// Valid pattern constant (UCIe: 00001111 × 4 = 0x0F0F0F0F)
// ─────────────────────────────────────────────────────────────────────────────
localparam [DATA_WIDTH-1:0] VALID_PATTERN_CODE = 32'h0F0F0F0F;

// ─────────────────────────────────────────────────────────────────────────────
// PLL_CLK domain registers
// ─────────────────────────────────────────────────────────────────────────────
reg [DATA_WIDTH-1:0] shift_reg;
reg [DATA_WIDTH-1:0] save_data;
reg                  r_data_pos;        // posedge capture of ser_data_in
reg                  prev_ser_data_in;  // previous negedge value (for edge detection)

// FSM
reg                  o_state;           // 0 = IDLE, 1 = RUNNING
reg [3:0]            o_count;           // 0..15 negedge cycles per frame

// Toggle-synchroniser for pll_clk → MB_clk CDC
reg                  save_data_toggle;
reg                  sync1_toggle;
reg                  sync2_toggle;
reg                  sync3_toggle;
wire                 valid_pulse;

// ─────────────────────────────────────────────────────────────────────────────
// Posedge capture: r_data_pos holds the bit sent at rising edge
// ─────────────────────────────────────────────────────────────────────────────
always @(posedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n)
        r_data_pos <= 1'b0;
    else
        r_data_pos <= ser_data_in;
end

// ─────────────────────────────────────────────────────────────────────────────
// Negedge: FSM + shift register
//   Shift order: LSB-first DDR, 2 bits per negedge cycle
//     shift_reg <= { ser_data_in[negedge], r_data_pos[posedge], shift_reg[DATA_WIDTH-1:2] }
//   At count==15 (end of 16th cycle) the shift is complete → snapshot.
// ─────────────────────────────────────────────────────────────────────────────
always @(negedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        shift_reg        <= {DATA_WIDTH{1'b0}};
        save_data        <= {DATA_WIDTH{1'b0}};
        save_data_toggle <= 1'b0;
        prev_ser_data_in <= 1'b0;
        o_state          <= 1'b0;   // IDLE
        o_count          <= 4'd0;
    end else begin
        // Free-running DDR shift register (always shifting regardless of FSM state)
        shift_reg <= {ser_data_in, r_data_pos, shift_reg[DATA_WIDTH-1:2]};
        prev_ser_data_in <= ser_data_in;

        case (o_state)
            1'b0: begin // IDLE — wait for rising edge (0→1) on valid lane
                if (ser_data_in && !prev_ser_data_in) begin
                    o_state <= 1'b1; // RUNNING
                    o_count <= 4'd0;
                end
            end

            1'b1: begin // RUNNING — count 16 negedge cycles
                if (o_count == 4'd15) begin
                    // Frame complete: snapshot the shift register
                    save_data        <= {r_data_pos, shift_reg[DATA_WIDTH-1:1]};
                    save_data_toggle <= ~save_data_toggle;  // trigger CDC

                    // Check if the next frame starts immediately (rising edge at boundary)
                    if (ser_data_in && !prev_ser_data_in) begin
                        o_state <= 1'b1; // back-to-back frame
                        o_count <= 4'd0;
                    end else begin
                        o_state <= 1'b0; // return to IDLE
                        o_count <= 4'd0;
                    end
                end else begin
                    o_count <= o_count + 4'd1;
                end
            end
        endcase
    end
end

// ─────────────────────────────────────────────────────────────────────────────
// Toggle Synchroniser: pll_clk → MB_clk  (3-FF)
// ─────────────────────────────────────────────────────────────────────────────
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

// 1-cycle pulse in MB_clk domain when a new 32-bit word has crossed the CDC
assign valid_pulse = (sync2_toggle != sync3_toggle);

// ─────────────────────────────────────────────────────────────────────────────
// MB_clk domain: output registers
// ─────────────────────────────────────────────────────────────────────────────

// par_data_out & de_ser_done: fire on every completed frame
always @(posedge MB_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        par_data_out <= {DATA_WIDTH{1'b0}};
        de_ser_done  <= 1'b0;
    end else begin
        de_ser_done <= 1'b0; // default: 1-cycle pulse only
        if (valid_pulse) begin
            par_data_out <= save_data;
            de_ser_done  <= 1'b1;
        end
    end
end

// enable_des_valid_frame: NON-STICKY, reflects the last received frame
always @(posedge MB_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        enable_des_valid_frame <= 1'b0;
    end else begin
        if (valid_pulse) begin
            enable_des_valid_frame <= (save_data == VALID_PATTERN_CODE) ? 1'b1 : 1'b0;
        end
    end
end

endmodule