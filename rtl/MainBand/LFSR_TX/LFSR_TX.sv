

module LFSR_TX #(
    parameter WIDTH = 32
)(
    input  logic        i_clk,                        // Clock signal
    input  logic        i_rst_n,                      // Active-low synchronous reset
    input  logic [2:0]  i_state,                      // Requested state from controller
    input  logic        i_scramble_en, // 1: scramble data, 0: pass pattern only
    input  logic [2:0]  i_width_deg_lfsr,        // Lane group selection
    input  logic        i_reversal_en,            // Enable physical lane reversal
    input  logic        i_active_state_entered,       // Pulse: active (DATA_TRANSFER) state entered

    // -------------------------------------------------------------------------
    // 16 input data lanes (indexed 0-15)
    // -------------------------------------------------------------------------
    input  logic [WIDTH-1:0] i_lane [0:15],

    // -------------------------------------------------------------------------
    // 16 output data lanes (indexed 0-15)
    // -------------------------------------------------------------------------
    output logic  [WIDTH-1:0] o_lane [0:15],
    output logic  o_ser_en_lfsr,
    output logic  o_Lfsr_tx_done,   // Pulses high when current LFSR/ID phase completes
    output logic  o_valid_frame_en    // High while frames are actively being transmitted
);

endmodule