// ====================================================================================================
// unit_D2C_lane_sel.sv — D2C Point Test Lane Control Selector
//
// This module decodes lane configurations combinationaly for the D2C phase.
// It maps the local/partner test enables and pattern setup to drive mainband TX/RX lane selectors.
// ====================================================================================================

module unit_D2C_lane_sel (
    input  logic       local_tx_pt_en,
    input  logic       partner_tx_pt_en,
    input  logic       local_rx_pt_en,
    input  logic       partner_rx_pt_en,
    input  logic [2:0] d2c_pattern_setup, // Bit0: Data, Bit1: Valid, Bit2: Clock

    // output logic [1:0] mb_tx_clk_lane_sel,
    // output logic [1:0] mb_tx_data_lane_sel,
    // output logic [1:0] mb_tx_val_lane_sel,
    // output logic [1:0] mb_tx_trk_lane_sel,

    output logic       mb_rx_clk_lane_sel,
    output logic       mb_rx_data_lane_sel,
    output logic       mb_rx_val_lane_sel,
    output logic       mb_rx_trk_lane_sel
);

    always_comb begin
        // Default posture (Inactive / D2C default state)
        // mb_tx_clk_lane_sel  = 2'b00;
        // mb_tx_data_lane_sel = 2'b00;
        // mb_tx_val_lane_sel  = 2'b00;
        // mb_tx_trk_lane_sel  = 2'b00;

        mb_rx_clk_lane_sel  = 1'b1;
        mb_rx_val_lane_sel  = 1'b1;
        mb_rx_data_lane_sel = 1'b1;
        mb_rx_trk_lane_sel  = 1'b0;

        if (local_tx_pt_en || partner_tx_pt_en) begin
            // Transmitter Mode:
            // mb_tx_clk_lane_sel  = d2c_pattern_setup[2] ? 2'b01 : 2'b00;
            // mb_tx_val_lane_sel  = d2c_pattern_setup[1] ? 2'b01 : 2'b00;
            // mb_tx_data_lane_sel = d2c_pattern_setup[0] ? 2'b01 : 2'b00;
            // mb_tx_trk_lane_sel  = 2'b00;

            mb_rx_clk_lane_sel  = 1'b1;
            mb_rx_val_lane_sel  = 1'b1;
            mb_rx_data_lane_sel = 1'b1;
            mb_rx_trk_lane_sel  = 1'b0;
        end else if (local_rx_pt_en || partner_rx_pt_en) begin
            // Receiver Mode:
            mb_rx_clk_lane_sel  = d2c_pattern_setup[2];
            mb_rx_val_lane_sel  = d2c_pattern_setup[1];
            mb_rx_data_lane_sel = d2c_pattern_setup[0];
            mb_rx_trk_lane_sel  = 1'b0;

            // mb_tx_clk_lane_sel  = 2'b00;
            // mb_tx_val_lane_sel  = 2'b00;
            // mb_tx_data_lane_sel = 2'b00;
            // mb_tx_trk_lane_sel  = 2'b00;
        end
    end

endmodule
