import sb_pkg::*;
import UCIe_pkg::*;

module DePacketizer (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [127:0] msg_in,
    input  logic         vld_in,
    output msg_no_e      msg_no_out,
    output logic [ 15:0] msginfo_r,
    output logic [ 63:0] payload_r,
    output logic         vld_r,
    output logic stall_rcvd
);
    
    sb_header_u header_in;
    logic is_req;
    msg_no_e msg_no_comb;
    logic error_flag;
    logic dp_calc,cp_calc;
    logic is_stall;
    always_comb begin

        // =====================================================
        // Defaults
        // =====================================================
        msg_no_comb  = NOTHING;
        header_in = msg_in [63:0];

        error_flag = 0;
        is_stall = header_in.msg.MsgInfo == 16'hffff ? 1'b1 : 1'b0; 
        // direction derived once (LSB rule: 1=req , 0=resp)

        is_req = header_in.msg.msgcode[0];

        // parity calculations
        cp_calc = ^msg_in [61:0];
        dp_calc = ^msg_in [127:64];

        if(header_in.msg.opcode == SB_MSG_WITH_64_DATA) begin
            error_flag = !((cp_calc == header_in.msg.cp) && (dp_calc == header_in.msg.dp));
        end
        else if(header_in.msg.opcode == SB_MSG_WITHOUT_DATA) begin
            error_flag = !(cp_calc == header_in.msg.cp) ;
        end
        else begin
            error_flag = 1'b1;
        end
        // =====================================================
        // Main Decode
        // =====================================================
        case (header_in.msg.msgcode)

            // =================================================
            // SBINIT_OFFRESET
            // =================================================
            SBINIT_OFFRESET_DOMAIN: begin
                if (header_in.msg.MsgSubcode == 8'h00)
                    msg_no_comb = SBINIT_Out_of_Reset;
                else begin
                    error_flag = 1;
                end
            end


            // =================================================
            // SBINIT REQ / RESP
            // =================================================
            SBINIT_REQ_DOMAIN,
            SBINIT_RESP_DOMAIN: begin

                case (header_in.msg.MsgSubcode)

                    8'h01:
                        msg_no_comb = is_req ?
                                     SBINIT_done_req :
                                     SBINIT_done_resp;
                    default: error_flag = 1;
                endcase
            end

            // =================================================
            // RDI DOMAIN
            // =================================================
            RDI_REQ_DOMAIN,
            RDI_RESP_DOMAIN: begin

                case (header_in.msg.MsgSubcode)

                    8'h01: msg_no_comb = is_req ?
                                        RDI_ACTIVE_REQ :
                                        RDI_ACTIVE_RSP;

                    8'h02: msg_no_comb = RDI_PMNAK_RSP;

                    8'h04: msg_no_comb = is_req ?
                                        RDI_L1_REQ :
                                        RDI_L1_RSP;

                    8'h08: msg_no_comb = is_req ?
                                        RDI_L2_REQ :
                                        RDI_L2_RSP;

                    8'h09: msg_no_comb = is_req ?
                                        RDI_LINK_RESET_REQ :
                                        RDI_LINK_RESET_RSP;

                    8'h0A: msg_no_comb = is_req ?
                                        RDI_LINK_ERROR_REQ :
                                        RDI_LINK_ERROR_RSP;

                    8'h0B: msg_no_comb = is_req ?
                                        RDI_RETRAIN_REQ :
                                        RDI_RETRAIN_RSP;

                    8'h0C: msg_no_comb = is_req ?
                                        RDI_DISABLE_REQ :
                                        RDI_DISABLE_RSP;

                    default: error_flag = 1;
                endcase
            end

            // =================================================
            // MBINIT DOMAIN
            // =================================================
            MBINIT_REQ_DOMAIN,
            MBINIT_RESP_DOMAIN: begin

                case (header_in.msg.MsgSubcode)

                    8'h00: msg_no_comb = is_req ?
                                        MBINIT_PARAM_configuration_req :
                                        MBINIT_PARAM_configuration_resp;

                    8'h01: msg_no_comb = is_req ?
                                        MBINIT_PARAM_SBFE_req :
                                        MBINIT_PARAM_SBFE_resp;

                    8'h02: msg_no_comb = is_req ?
                                        MBINIT_CAL_Done_req :
                                        MBINIT_CAL_Done_resp;

                    8'h03: msg_no_comb = is_req ?
                                        MBINIT_REPAIRCLK_init_req :
                                        MBINIT_REPAIRCLK_init_resp;

                    8'h04: msg_no_comb = is_req ?
                                        MBINIT_REPAIRCLK_result_req :
                                        MBINIT_REPAIRCLK_result_resp;

                    8'h08: msg_no_comb = is_req ?
                                        MBINIT_REPAIRCLK_done_req :
                                        MBINIT_REPAIRCLK_done_resp;

                    8'h09: msg_no_comb = is_req ?
                                        MBINIT_REPAIRVAL_init_req :
                                        MBINIT_REPAIRVAL_init_resp;

                    8'h0A: msg_no_comb = is_req ?
                                        MBINIT_REPAIRVAL_result_req :
                                        MBINIT_REPAIRVAL_result_resp;

                    8'h0C: msg_no_comb = is_req ?
                                        MBINIT_REPAIRVAL_done_req :
                                        MBINIT_REPAIRVAL_done_resp;

                    8'h0D: msg_no_comb = is_req ?
                                        MBINIT_REVERSALMB_init_req :
                                        MBINIT_REVERSALMB_init_resp;

                    8'h0E: msg_no_comb = is_req ?
                                        MBINIT_REVERSALMB_clear_error_req :
                                        MBINIT_REVERSALMB_clear_error_resp;

                    8'h0F: msg_no_comb = is_req ?
                                        MBINIT_REVERSALMB_result_req :
                                        MBINIT_REVERSALMB_result_resp;

                    8'h10: msg_no_comb = is_req ?
                                        MBINIT_REVERSALMB_done_req :
                                        MBINIT_REVERSALMB_done_resp;

                    8'h11: msg_no_comb = is_req ?
                                        MBINIT_REPAIRMB_start_req :
                                        MBINIT_REPAIRMB_start_resp;

                    8'h14: msg_no_comb = is_req ?
                                        MBINIT_REPAIRMB_apply_degrade_req :
                                        MBINIT_REPAIRMB_apply_degrade_resp;

                    8'h13: msg_no_comb = is_req ?
                                        MBINIT_REPAIRMB_end_req :
                                        MBINIT_REPAIRMB_end_resp;

                    8'h12: msg_no_comb = is_req ?
                        MBINIT_REPAIRMB_apply_repair_req :
                        MBINIT_REPAIRMB_apply_repair_resp;

                    default: error_flag = 1;
                endcase
            end


            // =================================================
            // MBTRAIN DOMAIN
            // =================================================
            MBTRAIN_REQ_DOMAIN,
            MBTRAIN_RESP_DOMAIN: begin

                case (header_in.msg.MsgSubcode)

                    8'h00: msg_no_comb = is_req ?
                                        MBTRAIN_VALVREF_start_req :
                                        MBTRAIN_VALVREF_start_resp;

                    8'h01: msg_no_comb = is_req ?
                                        MBTRAIN_VALVREF_end_req :
                                        MBTRAIN_VALVREF_end_resp;

                    8'h02: msg_no_comb = is_req ?
                                        MBTRAIN_DATAVREF_start_req :
                                        MBTRAIN_DATAVREF_start_resp;

                    8'h03: msg_no_comb = is_req ?
                                        MBTRAIN_DATAVREF_end_req :
                                        MBTRAIN_DATAVREF_end_resp;

                    8'h04: msg_no_comb = is_req ?
                                        MBTRAIN_SPEEDIDLE_done_req :
                                        MBTRAIN_SPEEDIDLE_done_resp;

                    8'h05: msg_no_comb = is_req ?
                                        MBTRAIN_TXSELFCAL_Done_req :
                                        MBTRAIN_TXSELFCAL_Done_resp;

                    8'h06: msg_no_comb = is_req ?
                                        MBTRAIN_RXCLKCAL_start_req :
                                        MBTRAIN_RXCLKCAL_start_resp;

                    8'h07: msg_no_comb = is_req ?
                                        MBTRAIN_RXCLKCAL_done_req :
                                        MBTRAIN_RXCLKCAL_done_resp;

                    8'h08: msg_no_comb = is_req ?
                                        MBTRAIN_VALTRAINCENTER_start_req :
                                        MBTRAIN_VALTRAINCENTER_start_resp;

                    8'h09: msg_no_comb = is_req ?
                                        MBTRAIN_VALTRAINCENTER_done_req :
                                        MBTRAIN_VALTRAINCENTER_done_resp;

                    8'h0A: msg_no_comb = is_req ?
                                        MBTRAIN_VALTRAINVREF_start_req :
                                        MBTRAIN_VALTRAINVREF_start_resp;

                    8'h0B: msg_no_comb = is_req ?
                                        MBTRAIN_VALTRAINVREF_end_req :
                                        MBTRAIN_VALTRAINVREF_end_resp;

                    8'h0C: msg_no_comb = is_req ?
                                        MBTRAIN_DATATRAINCENTER1_start_req :
                                        MBTRAIN_DATATRAINCENTER1_start_resp;

                    8'h0D: msg_no_comb = is_req ?
                                        MBTRAIN_DATATRAINCENTER1_end_req :
                                        MBTRAIN_DATATRAINCENTER1_end_resp;

                    8'h0E: msg_no_comb = is_req ?
                                        MBTRAIN_DATATRAINVREF_start_req :
                                        MBTRAIN_DATATRAINVREF_start_resp;

                    8'h10: msg_no_comb = is_req ?
                                        MBTRAIN_DATATRAINVREF_end_req :
                                        MBTRAIN_DATATRAINVREF_end_resp;

                    8'h11: msg_no_comb = is_req ?
                                        MBTRAIN_RXDESKEW_start_req :
                                        MBTRAIN_RXDESKEW_start_resp;

                    8'h12: msg_no_comb = is_req ?
                                        MBTRAIN_RXDESKEW_end_req :
                                        MBTRAIN_RXDESKEW_end_resp;

                    8'h13: msg_no_comb = is_req ?
                                        MBTRAIN_DATATRAINCENTER2_start_req :
                                        MBTRAIN_DATATRAINCENTER2_start_resp;

                    8'h14: msg_no_comb = is_req ?
                                        MBTRAIN_DATATRAINCENTER2_end_req :
                                        MBTRAIN_DATATRAINCENTER2_end_resp;

                    8'h15: msg_no_comb = is_req ?
                                        MBTRAIN_LINKSPEED_start_req :
                                        MBTRAIN_LINKSPEED_start_resp;

                    8'h16: msg_no_comb = is_req ?
                                        MBTRAIN_LINKSPEED_error_req :
                                        MBTRAIN_LINKSPEED_error_resp;

                    8'h17: msg_no_comb = is_req ?
                                        MBTRAIN_LINKSPEED_exit_to_repair_req :
                                        MBTRAIN_LINKSPEED_exit_to_repair_resp;

                    8'h18: msg_no_comb = is_req ?
                                        MBTRAIN_LINKSPEED_exit_to_speed_degrade_req :
                                        MBTRAIN_LINKSPEED_exit_to_speed_degrade_resp;

                    8'h19: msg_no_comb = is_req ?
                                        MBTRAIN_LINKSPEED_done_req :
                                        MBTRAIN_LINKSPEED_done_resp;

                    8'h1B: msg_no_comb = is_req ?
                                        MBTRAIN_REPAIR_init_req :
                                        MBTRAIN_REPAIR_init_resp;

                    8'h1C: msg_no_comb = is_req ?
                        MBTRAIN_REPAIR_apply_repair_req :
                        MBTRAIN_REPAIR_apply_repair_resp;

                    8'h1D: msg_no_comb = is_req ?
                                        MBTRAIN_REPAIR_end_req :
                                        MBTRAIN_REPAIR_end_resp;

                    8'h1E: msg_no_comb = is_req ?
                                        MBTRAIN_REPAIR_apply_degrade_req :
                                        MBTRAIN_REPAIR_apply_degrade_resp;

                    8'h1F: msg_no_comb = is_req ?
                        MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req :
                        MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp;


                    // =================================================
                    // CONFLICT AREA (0x1F)
                    // Used by:
                    //   1) MBTRAIN_LINKSPEED_exit_to_phy_retrain
                    //   2) MBTRAIN_RXDESKEW_EQ_Preset
                    //
                    // Needs LTSM state to resolve.
                    // =================================================
                    // 8'h1F:  intentionally unresolved
                    8'h20: msg_no_comb = is_req ?
                                        MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req :
                                        MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp;
                    8'h21: msg_no_comb = is_req ?
                                        MBTRAIN_RXCLKCAL_TCKN_L_shift_req :
                                        MBTRAIN_RXCLKCAL_TCKN_L_shift_resp;
                    8'h22: msg_no_comb = is_req ?
                                        RECAL_track_tx_adjust_req :
                                        RECAL_track_tx_adjust_resp;
                    default: error_flag = 1;
                endcase
            end


            // =================================================
            // RECAL DOMAIN
            // =================================================
            RECAL_REQ_DOMAIN,
            RECAL_RESP_DOMAIN: begin

                case (header_in.msg.MsgSubcode)

                    8'h00: msg_no_comb = is_req ?
                                        RECAL_track_pattern_init_req :
                                        RECAL_track_pattern_init_resp;

                    8'h01: msg_no_comb = is_req ?
                                        RECAL_track_pattern_done_req :
                                        RECAL_track_pattern_done_resp;
                    default: error_flag = 1;
                endcase
            end


            // =================================================
            // PHYRETRAIN
            // =================================================
            PHYRETRAIN_REQ_DOMAIN: begin
                if (header_in.msg.MsgSubcode == 8'h01) begin
                    msg_no_comb = PHYRETRAIN_retrain_start_req;
                end
                else begin
                    error_flag = 1;
                end
            end

            PHYRETRAIN_RESP_DOMAIN: begin
                if (header_in.msg.MsgSubcode == 8'h01) begin
                    msg_no_comb = PHYRETRAIN_retrain_start_resp;
                end
                else begin
                    error_flag = 1;
                end
            end


            // =================================================
            // TRAINERROR
            // =================================================
            TRAINERROR_REQ_DOMAIN: begin
                if (header_in.msg.MsgSubcode == 8'h00) begin
                    msg_no_comb = TRAINERROR_Entry_req;
                end
                else begin
                    error_flag = 1;
                end
            end

            TRAINERROR_RESP_DOMAIN: begin
                if (header_in.msg.MsgSubcode == 8'h00) begin
                    msg_no_comb = TRAINERROR_Entry_resp;
                end
                else begin
                    error_flag = 1;
                end
            end

            // =================================================
            // TEST DOMAIN
            // =================================================
            TEST_REQ_DOMAIN,
            TEST_RESP_DOMAIN: begin

                case (header_in.msg.MsgSubcode)

                    8'h01: msg_no_comb = is_req ?
                                        Start_Tx_Init_D_to_C_point_test_req :
                                        Start_Tx_Init_D_to_C_point_test_resp;

                    8'h02: msg_no_comb = is_req ?
                                        LFSR_clear_error_req :
                                        LFSR_clear_error_resp;

                    8'h03: msg_no_comb = is_req ?
                                        Tx_Init_D_to_C_results_req :
                                        Tx_Init_D_to_C_results_resp;

                    8'h04: msg_no_comb = is_req ?
                                        End_Tx_Init_D_to_C_point_test_req :
                                        End_Tx_Init_D_to_C_point_test_resp;

                    8'h05: msg_no_comb = is_req ?
                                        Start_Tx_Init_D_to_C_eye_sweep_req :
                                        Start_Tx_Init_D_to_C_eye_sweep_resp;

                    8'h06: msg_no_comb = is_req ?
                                        End_Tx_Init_D_to_C_eye_sweep_req :
                                        End_Tx_Init_D_to_C_eye_sweep_resp;

                    8'h07: msg_no_comb = is_req ?
                                        Start_Rx_Init_D_to_C_point_test_req :
                                        Start_Rx_Init_D_to_C_point_test_resp;

                    8'h08: msg_no_comb = is_req ?
                                        Rx_Init_D_to_C_Tx_Count_Done_req :
                                        Rx_Init_D_to_C_Tx_Count_Done_resp;

                    8'h09: msg_no_comb = is_req ?
                                        End_Rx_Init_D_to_C_point_test_req :
                                        End_Rx_Init_D_to_C_point_test_resp;

                    8'h0A: msg_no_comb = is_req ?
                                        Start_Rx_Init_D_to_C_eye_sweep_req :
                                        Start_Rx_Init_D_to_C_eye_sweep_resp;

                    8'h0B: msg_no_comb = is_req ?
                                        Rx_Init_D_to_C_results_req :
                                        Rx_Init_D_to_C_results_resp;

                    8'h0D: msg_no_comb = is_req ?
                                        End_Rx_Init_D_to_C_eye_sweep_req :
                                        End_Rx_Init_D_to_C_eye_sweep_resp;

                    default: error_flag = 1;
                endcase

            end
            RX_TEST_SWEEP_DONE_RESULT: begin
                if (header_in.msg.MsgSubcode == 8'h0C) begin
                    msg_no_comb = Rx_Init_D_to_C_sweep_done_with_results;
                end
                else begin
                    error_flag = 1;
                end
            end


        endcase

    end


    // --------------------------
    // Sequential
    // --------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vld_r <= 1'b0; // No valid message on reset
            msg_no_out <= NOTHING;
            stall_rcvd <= 1'b0;
            payload_r <= 64'b0;
            msginfo_r <= 16'b0;
        end else if(vld_in && !error_flag && msg_no_comb != NOTHING) begin

            msg_no_out <= msg_no_comb;
            stall_rcvd <= is_stall;
            vld_r <=1; // Indicate that the message is valid and rdy to be sent
            msginfo_r <= header_in.msg.MsgInfo;  
            payload_r <= msg_in [127:64];
        end else begin
            vld_r <= 1'b0; 
            msg_no_out <= NOTHING;
            stall_rcvd <= 0;
            payload_r <= 64'b0;
            msginfo_r <= 16'b0;
        end
    end

endmodule