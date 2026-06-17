`timescale 1ns/1ps
/*****   DESERIALIZER FOR DATA LANES  ******/
// =============================================================================
// Module: MB_DESERIALIZER
// Description:
//   Free-running DDR deserializer for a single data lane.
//   No external enable signal. Samples continuously after reset.
//
//   Shift register is free-running at full DDR rate (2 bits per pll_clk cycle).
//   A 16-cycle negedge counter matches the frame cadence of MB_DESERIALIZER_VALID
//   so both deserializers naturally stay frame-aligned (same pll_clk, same reset).
//
//   enable_des_valid_frame — MB_clk domain sticky flag from MB_DESERIALIZER_VALID.
//                            Set when F0F0F0F0/0F0F0F0F is confirmed on valid lane.
//                            Gates the parallel output in MB_clk domain.
//
//   CDC: 3-FF toggle synchroniser (pll_clk negedge → MB_clk posedge).
// =============================================================================

module MB_DESERIALIZER #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   MB_clk,
    input  wire                   pll_clk,
    input  wire                   i_rst_n,
    input  wire                   ser_data_in,
    input  wire                   enable_des_valid_frame,  // MB_clk sticky: valid pattern confirmed
    input  wire                   valid_ser_in,            // valid lane serial stream (for frame alignment)
    output reg  [DATA_WIDTH-1:0]  par_data_out,
    output reg                    de_ser_done
);

// ─────────────────────────────────────────────────────────────────────────────
// PLL_CLK domain registers
// ─────────────────────────────────────────────────────────────────────────────
reg [DATA_WIDTH-1:0] shift_reg;
reg [DATA_WIDTH-1:0] save_data;
reg                  r_data_pos;        // posedge capture

// 16-cycle negedge frame counter (mirrors valid deserializer cadence)
reg [3:0]            bit_cnt;
reg                  prev_valid_ser_in;
reg                  running;

// Toggle-synchroniser for pll_clk → MB_clk CDC
reg                  save_data_toggle;
reg                  sync1_toggle;
wire                 valid_pulse;

// ─────────────────────────────────────────────────────────────────────────────
// Posedge: capture even bit
// ─────────────────────────────────────────────────────────────────────────────
always @(posedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n)
        r_data_pos <= 1'b0;
    else
        r_data_pos <= ser_data_in;
end

// ─────────────────────────────────────────────────────────────────────────────
// Negedge: free-running shift + 16-cycle frame counter
//   LSB-first DDR: 2 bits per negedge cycle
//   { ser_data_in[negedge], r_data_pos[posedge], shift_reg[DATA_WIDTH-1:2] }
// ─────────────────────────────────────────────────────────────────────────────
always @(negedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        shift_reg         <= {DATA_WIDTH{1'b0}};
        save_data         <= {DATA_WIDTH{1'b0}};
        save_data_toggle  <= 1'b0;
        bit_cnt           <= 4'd0;
        prev_valid_ser_in <= 1'b0;
        running           <= 1'b0;
    end else begin
        // Always shift (free-running)
        shift_reg <= {ser_data_in, r_data_pos, shift_reg[DATA_WIDTH-1:2]};
        prev_valid_ser_in <= valid_ser_in;

        if (valid_ser_in && !prev_valid_ser_in && !running) begin
            running <= 1'b1;
            bit_cnt <= 4'd0;
        end else if (running) begin
            if (bit_cnt == 4'd15) begin
                bit_cnt          <= 4'd0;
                save_data        <= {r_data_pos, shift_reg[DATA_WIDTH-1:1]};
                save_data_toggle <= ~save_data_toggle;  // trigger CDC
                
                if (valid_ser_in && !prev_valid_ser_in) begin
                    running <= 1'b1;
                end else begin
                    running <= 1'b0;
                end
            end else begin
                bit_cnt <= bit_cnt + 4'd1;
            end
        end
    end
end

// ─────────────────────────────────────────────────────────────────────────────
// Toggle Synchroniser: pll_clk (negedge triggered) → MB_clk (1-FF)
// ─────────────────────────────────────────────────────────────────────────────
always @(posedge MB_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        sync1_toggle <= 1'b0;
    end else begin
        sync1_toggle <= save_data_toggle;
    end
end

// 1-cycle pulse in MB_clk domain when new word crossed CDC
assign valid_pulse = (save_data_toggle != sync1_toggle);

// ─────────────────────────────────────────────────────────────────────────────
// MB_clk domain: output logic
//   Output ONLY when both:
//     1. valid_pulse: a new 32-bit word is ready from pll_clk domain
//     2. enable_des_valid_frame: valid lane confirmed the valid pattern
// ─────────────────────────────────────────────────────────────────────────────
always @(posedge MB_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        par_data_out <= {DATA_WIDTH{1'b0}};
        de_ser_done  <= 1'b0;
    end else begin
        de_ser_done <= 1'b0; // default: 1-cycle pulse only
        if (valid_pulse && enable_des_valid_frame) begin
            par_data_out <= save_data;
            de_ser_done  <= 1'b1;
        end
    end
end

endmodule