// =============================================================================
// Module  : unit_mb_tx_reversal
// Project : UCIe 3.0 Main-Band Physical Layer
// Purpose : Swap serialized physical output lanes when lane reversal is enabled.
// =============================================================================

module unit_mb_tx_reversal #(
    parameter int NUM_LANES = 16
)(
    input  logic                    i_reversal_en,
    input  logic [NUM_LANES-1:0]    i_TD_P,
    output logic [NUM_LANES-1:0]    o_TD_P
);

    always_comb begin
        for (int i = 0; i < NUM_LANES; i = i + 1) begin
            o_TD_P[i] = i_reversal_en ? i_TD_P[NUM_LANES - 1 - i] : i_TD_P[i];
        end
    end

endmodule
