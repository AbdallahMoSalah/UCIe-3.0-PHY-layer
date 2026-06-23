// =============================================================================
// Module  : unit_mb_tx_reversal_array
// Project : UCIe 3.0 Main-Band Physical Layer
//
// Purpose : Parallel (pre-serialization) lane reversal. Functionally identical
//           to unit_mb_tx_reversal, but applied to the parallel lane WORDS right
//           after lfsr_tx instead of to the serialized 1-bit-per-lane bus after
//           the serializers.
//
//           Reversal only swaps lane positions (lane i <-> lane NUM_LANES-1-i).
//           Because every lane carries an independent word that is serialized on
//           its own dedicated serializer, reversing the parallel words before
//           serialization produces the exact same physical lane mapping as
//           reversing the serialized bits afterwards - so the function is
//           unchanged. This lets the reversal live in the digital design while
//           the serializers stay inside the analog hard macro.
//  Simulation only.
// =============================================================================

module unit_mb_tx_reversal_array #(
    parameter int DATA_WIDTH = 32,
    parameter int NUM_LANES  = 16
)(
    input  logic                    i_reversal_en,
    input  logic [DATA_WIDTH-1:0]   i_lane [0:NUM_LANES-1],
    output logic [DATA_WIDTH-1:0]   o_lane [0:NUM_LANES-1]
);

    always_comb begin
        for (int i = 0; i < NUM_LANES; i = i + 1) begin
            o_lane[i] = i_reversal_en ? i_lane[NUM_LANES-1-i] : i_lane[i];
        end
    end

endmodule
