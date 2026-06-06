`timescale 1ns/1ps
// =============================================================================
// Module  : unit_valid_deserializer
// Project : UCIe 3.0 Main-Band Physical Layer  (RX side)
// Purpose : Free-running DDR deserializer for the Valid lane (RVLD_P).
//
//  Operation
//  ---------
//  - Continuously shifts serial data into a 32-bit shift register using DDR
//    sampling (2 bits per pll_clk cycle, LSB first, same pairing convention
//    as MB_SERIALIZER / MB_DESERIALIZER).
//  - NO counter, NO enable gating — the shift register runs as long as
//    reset is de-asserted.
//  - The raw 32-bit shift register is exposed on `o_shift_reg` so that an
//    external combinational block (Valid_Frame_Detector) can check for the
//    valid-frame pattern (0x0F0F0F0F).
//
//  DDR bit pairing (matches MB_SERIALIZER)
//  ----------------------------------------
//   posedge n : capture even bit  word[2n]   → r_data_pos
//   negedge n : line carries odd  word[2n+1] → ser_data_in (live)
//   Shift on negedge:
//     shift_reg <= {ser_data_in, r_data_pos, shift_reg[31:2]}
// =============================================================================
module unit_valid_deserializer #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   pll_clk,       // high-speed serialization clock
    input  wire                   i_rst_n,       // active-low async reset
    input  wire                   ser_data_in,   // serial valid-lane input (RVLD_P)

    output wire [DATA_WIDTH-1:0]  o_shift_reg    // raw shift register (for frame detect)
);

// =========================================================================
// Internal registers
// =========================================================================
reg [DATA_WIDTH-1:0] shift_reg;
reg                  r_data_pos;   // even-bit capture register

// =========================================================================
// DDR Input Capture — posedge: capture even bit
// =========================================================================
always @(posedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        r_data_pos <= 1'b0;
    end else begin
        r_data_pos <= ser_data_in;   // word[2n] — HIGH phase
    end
end

// =========================================================================
// Shift on negedge — pair even + odd from same cycle, shift right 2
// =========================================================================
// At negedge n:
//   r_data_pos  = word[2n]   (captured at this cycle's posedge)
//   ser_data_in = word[2n+1] (live on the line during LOW phase)
// LSB first → earlier (even) bit goes to the lower position of the pair.
always @(negedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        shift_reg <= {DATA_WIDTH{1'b0}};
    end else begin
        shift_reg <= {ser_data_in, r_data_pos, shift_reg[DATA_WIDTH-1:2]};
    end
end

// =========================================================================
// Output — raw shift register exposed continuously
// =========================================================================
assign o_shift_reg = shift_reg;

endmodule
