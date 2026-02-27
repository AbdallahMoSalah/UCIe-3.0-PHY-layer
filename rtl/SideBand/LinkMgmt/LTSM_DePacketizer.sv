import sb_pkg::*;
import UCIe_pkg::*;

module LTSM_DE (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [127:0] ltsm_msg_in,
    input  logic         ltsm_vld_in,
    output logic [  7:0] msg_no_out,
    output logic [ 15:0] msginfo_r,
    output logic [ 63:0] payload_r,
    output logic         ltsm_vld_r
);
    

always_comb begin

    // =====================================================
    // Defaults
    // =====================================================
    msg_no_out  = '0;
    msginfo_out = header_in.MsgInfo;
    payload_out = payload_in;

    // direction derived once (LSB rule: 1=req , 0=resp)
    logic is_req;
    is_req = header_in.msgcode[0];

    // =====================================================
    // Main Decode
    // =====================================================
    case (header_in.msgcode)

        // =================================================
        // SBINIT_OFFRESET
        // =================================================
        SBINIT_OFFRESET_DOMAIN: begin
            msg_no_out = SBINIT_Out_of_Reset;
        end


        // =================================================
        // SBINIT REQ / RESP
        // =================================================
        SBINIT_REQ_DOMAIN,
        SBINIT_RESP_DOMAIN: begin

            case (header_in.MsgSubcode)

                8'h01:
                    msg_no_out = is_req ?
                                 SBINIT_done_req :
                                 SBINIT_done_resp;

            endcase
        end


        // =================================================
        // MBINIT DOMAIN
        // =================================================
        MBINIT_REQ_DOMAIN,
        MBINIT_RESP_DOMAIN: begin

            case (header_in.MsgSubcode)

                8'h00: msg_no_out = is_req ?
                                    MBINIT_PARAM_configuration_req :
                                    MBINIT_PARAM_configuration_resp;

                8'h01: msg_no_out = is_req ?
                                    MBINIT_PARAM_SBFE_req :
                                    MBINIT_PARAM_SBFE_resp;

                8'h02: msg_no_out = is_req ?
                                    MBINIT_CAL_Done_req :
                                    MBINIT_CAL_Done_resp;

                8'h03: msg_no_out = is_req ?
                                    MBINIT_REPAIRCLK_init_req :
                                    MBINIT_REPAIRCLK_init_resp;

                8'h04: msg_no_out = is_req ?
                                    MBINIT_REPAIRCLK_result_req :
                                    MBINIT_REPAIRCLK_result_resp;

                8'h08: msg_no_out = is_req ?
                                    MBINIT_REPAIRCLK_done_req :
                                    MBINIT_REPAIRCLK_done_resp;

                8'h09: msg_no_out = is_req ?
                                    MBINIT_REPAIRVAL_init_req :
                                    MBINIT_REPAIRVAL_init_resp;

                8'h0A: msg_no_out = is_req ?
                                    MBINIT_REPAIRVAL_result_req :
                                    MBINIT_REPAIRVAL_result_resp;

                8'h0C: msg_no_out = is_req ?
                                    MBINIT_REPAIRVAL_done_req :
                                    MBINIT_REPAIRVAL_done_resp;

                8'h0D: msg_no_out = is_req ?
                                    MBINIT_REVERSALMB_init_req :
                                    MBINIT_REVERSALMB_init_resp;

                8'h0E: msg_no_out = is_req ?
                                    MBINIT_REVERSALMB_clear_error_req :
                                    MBINIT_REVERSALMB_clear_error_resp;

                8'h0F: msg_no_out = is_req ?
                                    MBINIT_REVERSALMB_result_req :
                                    MBINIT_REVERSALMB_result_resp;

                8'h10: msg_no_out = is_req ?
                                    MBINIT_REVERSALMB_done_req :
                                    MBINIT_REVERSALMB_done_resp;

                8'h11: msg_no_out = is_req ?
                                    MBINIT_REPAIRMB_start_req :
                                    MBINIT_REPAIRMB_start_resp;

                8'h14: msg_no_out = is_req ?
                                    MBINIT_REPAIRMB_apply_degrade_req :
                                    MBINIT_REPAIRMB_apply_degrade_resp;

                8'h13: msg_no_out = is_req ?
                                    MBINIT_REPAIRMB_end_req :
                                    MBINIT_REPAIRMB_end_resp;

            endcase
        end


        // =================================================
        // MBTRAIN DOMAIN
        // =================================================
        MBTRAIN_REQ_DOMAIN,
        MBTRAIN_RESP_DOMAIN: begin

            case (header_in.MsgSubcode)

                8'h00: msg_no_out = is_req ?
                                    MBTRAIN_VALVREF_start_req :
                                    MBTRAIN_VALVREF_start_resp;

                8'h01: msg_no_out = is_req ?
                                    MBTRAIN_VALVREF_end_req :
                                    MBTRAIN_VALVREF_end_resp;

                8'h02: msg_no_out = is_req ?
                                    MBTRAIN_DATAVREF_start_req :
                                    MBTRAIN_DATAVREF_start_resp;

                8'h03: msg_no_out = is_req ?
                                    MBTRAIN_DATAVREF_end_req :
                                    MBTRAIN_DATAVREF_end_resp;

                8'h04: msg_no_out = is_req ?
                                    MBTRAIN_SPEEDIDLE_done_req :
                                    MBTRAIN_SPEEDIDLE_done_resp;

                8'h05: msg_no_out = is_req ?
                                    MBTRAIN_TXSELFCAL_Done_req :
                                    MBTRAIN_TXSELFCAL_Done_resp;

                8'h06: msg_no_out = is_req ?
                                    MBTRAIN_RXCLKCAL_start_req :
                                    MBTRAIN_RXCLKCAL_start_resp;

                8'h07: msg_no_out = is_req ?
                                    MBTRAIN_RXCLKCAL_done_req :
                                    MBTRAIN_RXCLKCAL_done_resp;

                8'h08: msg_no_out = is_req ?
                                    MBTRAIN_VALTRAINCENTER_start_req :
                                    MBTRAIN_VALTRAINCENTER_start_resp;

                8'h09: msg_no_out = is_req ?
                                    MBTRAIN_VALTRAINCENTER_done_req :
                                    MBTRAIN_VALTRAINCENTER_done_resp;

                8'h0A: msg_no_out = is_req ?
                                    MBTRAIN_VALTRAINVREF_start_req :
                                    MBTRAIN_VALTRAINVREF_start_resp;

                8'h0B: msg_no_out = is_req ?
                                    MBTRAIN_VALTRAINVREF_end_req :
                                    MBTRAIN_VALTRAINVREF_end_resp;

                8'h0C: msg_no_out = is_req ?
                                    MBTRAIN_DATATRAINCENTER1_start_req :
                                    MBTRAIN_DATATRAINCENTER1_start_resp;

                8'h0D: msg_no_out = is_req ?
                                    MBTRAIN_DATATRAINCENTER1_end_req :
                                    MBTRAIN_DATATRAINCENTER1_end_resp;

                8'h0E: msg_no_out = is_req ?
                                    MBTRAIN_DATATRAINVREF_start_req :
                                    MBTRAIN_DATATRAINVREF_start_resp;

                8'h10: msg_no_out = is_req ?
                                    MBTRAIN_DATATRAINVREF_end_req :
                                    MBTRAIN_DATATRAINVREF_end_resp;

                8'h11: msg_no_out = is_req ?
                                    MBTRAIN_RXDESKEW_start_req :
                                    MBTRAIN_RXDESKEW_start_resp;

                8'h12: msg_no_out = is_req ?
                                    MBTRAIN_RXDESKEW_end_req :
                                    MBTRAIN_RXDESKEW_end_resp;

                8'h13: msg_no_out = is_req ?
                                    MBTRAIN_DATATRAINCENTER2_start_req :
                                    MBTRAIN_DATATRAINCENTER2_start_resp;

                8'h14: msg_no_out = is_req ?
                                    MBTRAIN_DATATRAINCENTER2_end_req :
                                    MBTRAIN_DATATRAINCENTER2_end_resp;

                8'h15: msg_no_out = is_req ?
                                    MBTRAIN_LINKSPEED_start_req :
                                    MBTRAIN_LINKSPEED_start_resp;

                8'h16: msg_no_out = is_req ?
                                    MBTRAIN_LINKSPEED_error_req :
                                    MBTRAIN_LINKSPEED_error_resp;

                8'h17: msg_no_out = is_req ?
                                    MBTRAIN_LINKSPEED_exit_to_repair_req :
                                    MBTRAIN_LINKSPEED_exit_to_repair_resp;

                8'h18: msg_no_out = is_req ?
                                    MBTRAIN_LINKSPEED_exit_to_speed_degrade_req :
                                    MBTRAIN_LINKSPEED_exit_to_speed_degrade_resp;

                8'h19: msg_no_out = is_req ?
                                    MBTRAIN_LINKSPEED_done_req :
                                    MBTRAIN_LINKSPEED_done_resp;

                8'h1B: msg_no_out = is_req ?
                                    MBTRAIN_REPAIR_init_req :
                                    MBTRAIN_REPAIR_init_resp;

                8'h1D: msg_no_out = is_req ?
                                    MBTRAIN_REPAIR_end_req :
                                    MBTRAIN_REPAIR_end_resp;

                8'h1E: msg_no_out = is_req ?
                                    MBTRAIN_REPAIR_apply_degrade_req :
                                    MBTRAIN_REPAIR_apply_degrade_resp;

                // =================================================
                // CONFLICT AREA (0x1F)
                // Used by:
                //   1) MBTRAIN_LINKSPEED_exit_to_phy_retrain
                //   2) MBTRAIN_RXDESKEW_EQ_Preset
                //
                // Needs LTSM state to resolve.
                // =================================================
                // 8'h1F:  intentionally unresolved
                8'h20: msg_no_out = is_req ?
                                    MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req :
                                    MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp;
                8'h21: msg_no_out = is_req ?
                                    MBTRAIN_RXCLKCAL_TCKN_L_shift_req :
                                    MBTRAIN_RXCLKCAL_TCKN_L_shift_resp;
                8'h22: msg_no_out = is_req ?
                                    RECAL_track_tx_adjust_req :
                                    RECAL_track_tx_adjust_resp;

            endcase
        end


        // =================================================
        // RECAL DOMAIN
        // =================================================
        RECAL_REQ_DOMAIN,
        RECAL_RESP_DOMAIN: begin

            case (header_in.MsgSubcode)

                8'h00: msg_no_out = is_req ?
                                    RECAL_track_pattern_init_req :
                                    RECAL_track_pattern_init_resp;

                8'h01: msg_no_out = is_req ?
                                    RECAL_track_pattern_done_req :
                                    RECAL_track_pattern_done_resp;

            endcase
        end


        // =================================================
        // PHYRETRAIN
        // =================================================
        PHYRETRAIN_REQ_DOMAIN: begin
            if (header_in.MsgSubcode == 8'h01)
                msg_no_out = PHYRETRAIN_retrain_start_req;
        end

        PHYRETRAIN_RESP_DOMAIN: begin
            if (header_in.MsgSubcode == 8'h01)
                msg_no_out = PHYRETRAIN_retrain_start_resp;
        end


        // =================================================
        // TRAINERROR
        // =================================================
        TRAINERROR_REQ_DOMAIN:
            msg_no_out = TRAINERROR_Entry_req;

        TRAINERROR_RESP_DOMAIN:
            msg_no_out = TRAINERROR_Entry_resp;

    endcase

end
endmodule