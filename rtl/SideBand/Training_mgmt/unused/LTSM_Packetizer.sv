import sb_pkg::*;
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;

module LTSM_Packetizer (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [ 63:0] ltsm_msg_data_send,
    input  logic [ 15:0] ltsm_msg_info_send,
    input  logic [  7:0] msg_no_send,
    input  logic         ltsm_valid_send,
    input  logic         push_rdy,
    input logic          stall_send,
    output logic [127:0] ltsm_msg,
    output logic         ltsm_vld,
    output logic         ltsm_rdy
);


sb_header_u header_comb,header_reg;
logic [63:0] payload;

logic is_there_data;
logic is_req;
assign ltsm_rdy = push_rdy;

always_comb begin

    // =====================================================
    // Defaults
    // =====================================================
    header_comb             = '0;
    header_comb.msg.dstid       = REMOTE_PHY;
    header_comb.msg.srcid       = PHY;
    header_comb.msg.MsgInfo     = ltsm_msg_info_send;
    is_there_data           = 0;
    is_req = msg_no_send[0];

    // =====================================================
    // RDI DOMAIN
    // =====================================================
    if (msg_no_send >= RDI_ACTIVE_REQ && msg_no_send <= RDI_PMNAK_RSP && msg_no_send != NOP) begin
         // msgcode
        if (msg_no_send[0]) begin
            header_comb.msg.msgcode = RDI_REQ_DOMAIN;  // Request
        end else begin
            header_comb.msg.msgcode = RDI_RESP_DOMAIN;  // Response
        end

        // subcode mapping
        case (msg_no_send)
            RDI_ACTIVE_REQ, RDI_ACTIVE_RSP:         header_comb.msg.MsgSubcode = 8'h01;
            RDI_PMNAK_RSP:                      header_comb.msg.MsgSubcode = 8'h02;
            RDI_L1_REQ, RDI_L1_RSP:                 header_comb.msg.MsgSubcode = 8'h04;
            RDI_L2_REQ, RDI_L2_RSP:                 header_comb.msg.MsgSubcode = 8'h08;
            RDI_LINK_RESET_REQ, RDI_LINK_RESET_RSP: header_comb.msg.MsgSubcode = 8'h09;
            RDI_LINK_ERROR_REQ, RDI_LINK_ERROR_RSP: header_comb.msg.MsgSubcode = 8'h0A;
            RDI_RETRAIN_REQ, RDI_RETRAIN_RSP:       header_comb.msg.MsgSubcode = 8'h0B;
            RDI_DISABLE_REQ, RDI_DISABLE_RSP:       header_comb.msg.MsgSubcode = 8'h0C;
        endcase
        header_comb.msg.MsgInfo     = stall_send ? 16'hffff : 16'h0000;
  
    end

    // =====================================================
    // SBINIT DOMAIN
    // =====================================================
    else if (msg_no_send >= SBINIT_Out_of_Reset && msg_no_send <= SBINIT_done_resp) begin // لو عايز تبسطها ماشي كنت عايز اخليها شبه الي تحت مش فارقه 
      if (msg_no_send == SBINIT_Out_of_Reset) header_comb.msg.msgcode = SBINIT_OFFRESET_DOMAIN;
      else if (msg_no_send[0] == 1'b1) header_comb.msg.msgcode = SBINIT_REQ_DOMAIN;
      else header_comb.msg.msgcode = SBINIT_RESP_DOMAIN;
      case (msg_no_send)
        SBINIT_Out_of_Reset: header_comb.msg.MsgSubcode = 8'h00;
        SBINIT_done_req:     header_comb.msg.MsgSubcode = 8'h01;
        SBINIT_done_resp:    header_comb.msg.MsgSubcode = 8'h02;
      endcase
    end

    

    // =====================================================
    // MBINIT DOMAIN
    // =====================================================
    else if (msg_no_send >= MBINIT_PARAM_configuration_req &&
             msg_no_send <= MBINIT_REPAIRMB_end_resp) begin

        if (msg_no_send[0] == 1'b1)
            header_comb.msg.msgcode = MBINIT_REQ_DOMAIN;
        else
            header_comb.msg.msgcode = MBINIT_RESP_DOMAIN;

        case (msg_no_send)

            MBINIT_PARAM_configuration_req,
            MBINIT_PARAM_configuration_resp: begin
                header_comb.msg.MsgSubcode = 8'h00; is_there_data = 1'b1;
            end

            MBINIT_PARAM_SBFE_req,
            MBINIT_PARAM_SBFE_resp: begin
                header_comb.msg.MsgSubcode = 8'h01; is_there_data = 1'b1;
            end

            MBINIT_CAL_Done_req,
            MBINIT_CAL_Done_resp:
                header_comb.msg.MsgSubcode = 8'h02;

            // ---------------- REPAIRCLK ----------------
            MBINIT_REPAIRCLK_init_req,
            MBINIT_REPAIRCLK_init_resp:
                header_comb.msg.MsgSubcode = 8'h03;

            MBINIT_REPAIRCLK_result_req,
            MBINIT_REPAIRCLK_result_resp:
                header_comb.msg.MsgSubcode = 8'h04;

            MBINIT_REPAIRCLK_done_req,
            MBINIT_REPAIRCLK_done_resp:
                header_comb.msg.MsgSubcode = 8'h08;

            // ---------------- REPAIRVAL ----------------
            MBINIT_REPAIRVAL_init_req,
            MBINIT_REPAIRVAL_init_resp:
                header_comb.msg.MsgSubcode = 8'h09;

            MBINIT_REPAIRVAL_result_req,
            MBINIT_REPAIRVAL_result_resp:
                header_comb.msg.MsgSubcode = 8'h0A;

            MBINIT_REPAIRVAL_done_req,
            MBINIT_REPAIRVAL_done_resp:
                header_comb.msg.MsgSubcode = 8'h0C;

            // ---------------- REVERSALMB ----------------
            MBINIT_REVERSALMB_init_req,
            MBINIT_REVERSALMB_init_resp:
                header_comb.msg.MsgSubcode = 8'h0D;

            MBINIT_REVERSALMB_clear_error_req,
            MBINIT_REVERSALMB_clear_error_resp:
                header_comb.msg.MsgSubcode = 8'h0E;

            MBINIT_REVERSALMB_result_req,
            MBINIT_REVERSALMB_result_resp: begin
                header_comb.msg.MsgSubcode = 8'h0F; is_there_data = !is_req;
            end

            MBINIT_REVERSALMB_done_req,
            MBINIT_REVERSALMB_done_resp:
                header_comb.msg.MsgSubcode = 8'h10;

            // ---------------- REPAIRMB ----------------
            MBINIT_REPAIRMB_start_req,
            MBINIT_REPAIRMB_start_resp:
                header_comb.msg.MsgSubcode = 8'h11;

            MBINIT_REPAIRMB_apply_repair_req,
            MBINIT_REPAIRMB_apply_repair_resp: begin
                header_comb.msg.MsgSubcode = 8'h12; is_there_data = is_req;
            end

            MBINIT_REPAIRMB_end_req,
            MBINIT_REPAIRMB_end_resp:
                header_comb.msg.MsgSubcode = 8'h13;

            MBINIT_REPAIRMB_apply_degrade_req,
            MBINIT_REPAIRMB_apply_degrade_resp:
                header_comb.msg.MsgSubcode = 8'h14;

        endcase
    end


    // =====================================================
    // MBTRAIN DOMAIN (B5 / BA)
    // includes RECAL_track_tx_adjust
    // =====================================================
    else if ( (msg_no_send >= MBTRAIN_VALVREF_start_req &&
               msg_no_send <= MBTRAIN_REPAIR_end_resp)
              ||
              (msg_no_send == RECAL_track_tx_adjust_req)
              ||
              (msg_no_send == RECAL_track_tx_adjust_resp)
            ) begin

        if (msg_no_send[0] == 1'b1)
            header_comb.msg.msgcode = MBTRAIN_REQ_DOMAIN;
        else
            header_comb.msg.msgcode = MBTRAIN_RESP_DOMAIN;

        case (msg_no_send)

            // ---------- VALVREF ----------
            MBTRAIN_VALVREF_start_req,
            MBTRAIN_VALVREF_start_resp:
                header_comb.msg.MsgSubcode = 8'h00;

            MBTRAIN_VALVREF_end_req,
            MBTRAIN_VALVREF_end_resp:
                header_comb.msg.MsgSubcode = 8'h01;

            // ---------- DATAVREF ----------
            MBTRAIN_DATAVREF_start_req,
            MBTRAIN_DATAVREF_start_resp:
                header_comb.msg.MsgSubcode = 8'h02;

            MBTRAIN_DATAVREF_end_req,
            MBTRAIN_DATAVREF_end_resp:
                header_comb.msg.MsgSubcode = 8'h03;

            // ---------- SPEEDIDLE ----------
            MBTRAIN_SPEEDIDLE_done_req,
            MBTRAIN_SPEEDIDLE_done_resp:
                header_comb.msg.MsgSubcode = 8'h04;

            // ---------- TXSELFCAL ----------
            MBTRAIN_TXSELFCAL_Done_req,
            MBTRAIN_TXSELFCAL_Done_resp:
                header_comb.msg.MsgSubcode = 8'h05;

            // ---------- RXCLKCAL ----------
            MBTRAIN_RXCLKCAL_start_req,
            MBTRAIN_RXCLKCAL_start_resp:
                header_comb.msg.MsgSubcode = 8'h06;

            MBTRAIN_RXCLKCAL_done_req,
            MBTRAIN_RXCLKCAL_done_resp:
                header_comb.msg.MsgSubcode = 8'h07;

            MBTRAIN_RXCLKCAL_TCKN_L_shift_req,
            MBTRAIN_RXCLKCAL_TCKN_L_shift_resp:
                header_comb.msg.MsgSubcode = 8'h21;
            // ---------- VALTRAINCENTER ----------
            MBTRAIN_VALTRAINCENTER_start_req,
            MBTRAIN_VALTRAINCENTER_start_resp:
                header_comb.msg.MsgSubcode = 8'h08;

            MBTRAIN_VALTRAINCENTER_done_req,
            MBTRAIN_VALTRAINCENTER_done_resp:
                header_comb.msg.MsgSubcode = 8'h09;

            // ---------- VALTRAINVREF ----------
            MBTRAIN_VALTRAINVREF_start_req,
            MBTRAIN_VALTRAINVREF_start_resp:
                header_comb.msg.MsgSubcode = 8'h0A;

            MBTRAIN_VALTRAINVREF_end_req,
            MBTRAIN_VALTRAINVREF_end_resp:
                header_comb.msg.MsgSubcode = 8'h0B;

            // ---------- DATATRAINCENTER1 ----------
            MBTRAIN_DATATRAINCENTER1_start_req,
            MBTRAIN_DATATRAINCENTER1_start_resp:
                header_comb.msg.MsgSubcode = 8'h0C;

            MBTRAIN_DATATRAINCENTER1_end_req,
            MBTRAIN_DATATRAINCENTER1_end_resp:
                header_comb.msg.MsgSubcode = 8'h0D;

            // ---------- DATATRAINVREF ----------
            MBTRAIN_DATATRAINVREF_start_req,
            MBTRAIN_DATATRAINVREF_start_resp:
                header_comb.msg.MsgSubcode = 8'h0E;

            MBTRAIN_DATATRAINVREF_end_req,
            MBTRAIN_DATATRAINVREF_end_resp:
                header_comb.msg.MsgSubcode = 8'h10;

            // ---------- RXDESKEW ----------
            MBTRAIN_RXDESKEW_start_req,
            MBTRAIN_RXDESKEW_start_resp:
                header_comb.msg.MsgSubcode = 8'h11;

            MBTRAIN_RXDESKEW_end_req,
            MBTRAIN_RXDESKEW_end_resp:
                header_comb.msg.MsgSubcode = 8'h12;
            
            MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req,
            MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp:
                header_comb.msg.MsgSubcode = 8'h20;


            // ---------- DATATRAINCENTER2 ----------
            MBTRAIN_DATATRAINCENTER2_start_req,
            MBTRAIN_DATATRAINCENTER2_start_resp:
                header_comb.msg.MsgSubcode = 8'h13;

            MBTRAIN_DATATRAINCENTER2_end_req,
            MBTRAIN_DATATRAINCENTER2_end_resp:
                header_comb.msg.MsgSubcode = 8'h14;

            // ---------- LINKSPEED ----------
            MBTRAIN_LINKSPEED_start_req,
            MBTRAIN_LINKSPEED_start_resp:
                header_comb.msg.MsgSubcode = 8'h15;

            MBTRAIN_LINKSPEED_error_req,
            MBTRAIN_LINKSPEED_error_resp:
                header_comb.msg.MsgSubcode = 8'h16;

            MBTRAIN_LINKSPEED_exit_to_repair_req,
            MBTRAIN_LINKSPEED_exit_to_repair_resp:
                header_comb.msg.MsgSubcode = 8'h17;

            MBTRAIN_LINKSPEED_exit_to_speed_degrade_req,
            MBTRAIN_LINKSPEED_exit_to_speed_degrade_resp:
                header_comb.msg.MsgSubcode = 8'h18;

            MBTRAIN_LINKSPEED_done_req,
            MBTRAIN_LINKSPEED_done_resp:
                header_comb.msg.MsgSubcode = 8'h19;

            MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req,
            MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp:
                header_comb.msg.MsgSubcode = 8'h1F;

            // ---------- REPAIR ----------
            MBTRAIN_REPAIR_init_req,
            MBTRAIN_REPAIR_init_resp:
                header_comb.msg.MsgSubcode = 8'h1B;
            
            MBTRAIN_REPAIR_apply_repair_req,
            MBTRAIN_REPAIR_apply_repair_resp: begin
                header_comb.msg.MsgSubcode = 8'h1C; is_there_data = is_req;
            end

            MBTRAIN_REPAIR_end_req,
            MBTRAIN_REPAIR_end_resp:
                header_comb.msg.MsgSubcode = 8'h1D;


            MBTRAIN_REPAIR_apply_degrade_req,
            MBTRAIN_REPAIR_apply_degrade_resp:
                header_comb.msg.MsgSubcode = 8'h1E;


            // ---------- RECAL TX ADJUST ----------
            RECAL_track_tx_adjust_req,
            RECAL_track_tx_adjust_resp:
                header_comb.msg.MsgSubcode = 8'h22;

        endcase
    end


    // =====================================================
    // RECAL PATTERN DOMAIN (D5 / DA)
    // =====================================================
    else if (msg_no_send == RECAL_track_pattern_init_req || //هنا مختلفه واخدها من شات فمكسل اخليها شبه الي فوق 
             msg_no_send == RECAL_track_pattern_init_resp) begin

        header_comb.msg.msgcode = (msg_no_send[0] == 1'b1) ?
                   RECAL_REQ_DOMAIN :
                   RECAL_RESP_DOMAIN;

        header_comb.msg.MsgSubcode = 8'h00;
    end
    else if (msg_no_send == RECAL_track_pattern_done_req ||
             msg_no_send == RECAL_track_pattern_done_resp) begin

        header_comb.msg.msgcode = (msg_no_send[0] == 1'b1) ?
                   RECAL_REQ_DOMAIN :
                   RECAL_RESP_DOMAIN;

        header_comb.msg.MsgSubcode = 8'h01;
    end


    // =====================================================
    // PHYRETRAIN
    // =====================================================
    else if (msg_no_send == PHYRETRAIN_retrain_start_req) begin
        header_comb.msg.msgcode    = PHYRETRAIN_REQ_DOMAIN;
        header_comb.msg.MsgSubcode = 8'h01;
    end
    else if (msg_no_send == PHYRETRAIN_retrain_start_resp) begin
        header_comb.msg.msgcode    = PHYRETRAIN_RESP_DOMAIN;
        header_comb.msg.MsgSubcode = 8'h01;
    end
                                                                    // دي والي تحتيها مش مستاهلين برضو بس كسلت اغيرهم ظبط بقا 

    // =====================================================
    // TRAINERROR
    // =====================================================
    else if (msg_no_send == TRAINERROR_Entry_req) begin
        header_comb.msg.msgcode    = TRAINERROR_REQ_DOMAIN;
        header_comb.msg.MsgSubcode = 8'h00;
    end
    else if (msg_no_send == TRAINERROR_Entry_resp) begin
        header_comb.msg.msgcode    = TRAINERROR_RESP_DOMAIN;
        header_comb.msg.MsgSubcode = 8'h00;
    end

    // =====================================================
    // TEST DOMAIN
    // =====================================================
    else if (msg_no_send >= Start_Tx_Init_D_to_C_point_test_req &&
             msg_no_send <= End_Rx_Init_D_to_C_eye_sweep_resp) begin

        if (msg_no_send[0] == 1'b1)
            header_comb.msg.msgcode = TEST_REQ_DOMAIN;
        else
            header_comb.msg.msgcode = TEST_RESP_DOMAIN;

        case (msg_no_send)

            Start_Tx_Init_D_to_C_point_test_req,
            Start_Tx_Init_D_to_C_point_test_resp: begin 
                header_comb.msg.MsgSubcode = 8'h01; is_there_data = is_req;
            end

            LFSR_clear_error_req,
            LFSR_clear_error_resp:
                header_comb.msg.MsgSubcode = 8'h02;

            Tx_Init_D_to_C_results_req,
            Tx_Init_D_to_C_results_resp: begin
                header_comb.msg.MsgSubcode = 8'h03; is_there_data = !is_req;
            end

            End_Tx_Init_D_to_C_point_test_req,
            End_Tx_Init_D_to_C_point_test_resp:
                header_comb.msg.MsgSubcode = 8'h04;

            Start_Tx_Init_D_to_C_eye_sweep_req,
            Start_Tx_Init_D_to_C_eye_sweep_resp: begin
                header_comb.msg.MsgSubcode = 8'h05; is_there_data = is_req;
            end

            End_Tx_Init_D_to_C_eye_sweep_req,
            End_Tx_Init_D_to_C_eye_sweep_resp:
                header_comb.msg.MsgSubcode = 8'h06;

            // ---------------- REPAIRVAL ----------------
            Start_Rx_Init_D_to_C_point_test_req,
            Start_Rx_Init_D_to_C_point_test_resp: begin
                header_comb.msg.MsgSubcode = 8'h07; is_there_data = is_req;
            end

            Rx_Init_D_to_C_Tx_Count_Done_req,
            Rx_Init_D_to_C_Tx_Count_Done_resp:
                header_comb.msg.MsgSubcode = 8'h08;

            End_Rx_Init_D_to_C_point_test_req,
            End_Rx_Init_D_to_C_point_test_resp:
                header_comb.msg.MsgSubcode = 8'h09;

            // ---------------- REVERSALMB ----------------
            Start_Rx_Init_D_to_C_eye_sweep_req,
            Start_Rx_Init_D_to_C_eye_sweep_resp: begin
                header_comb.msg.MsgSubcode = 8'h0A; is_there_data = is_req;
            end

            Rx_Init_D_to_C_results_req,
            Rx_Init_D_to_C_results_resp: begin
                header_comb.msg.MsgSubcode = 8'h0B; is_there_data = !is_req;
            end

            End_Rx_Init_D_to_C_eye_sweep_req,
            End_Rx_Init_D_to_C_eye_sweep_resp:
                header_comb.msg.MsgSubcode = 8'h0D;

        endcase
    end
    else if (msg_no_send == Rx_Init_D_to_C_sweep_done_with_results) begin

        header_comb.msg.msgcode = RX_TEST_SWEEP_DONE_RESULT;

        header_comb.msg.MsgSubcode = 8'h0C;
        is_there_data = 1'b1;
    end



    header_comb.msg.dp = is_there_data ? ^ltsm_msg_data_send : 1'b0;
    header_comb.msg.opcode = is_there_data ? SB_MSG_WITH_64_DATA : SB_MSG_WITHOUT_DATA;
    header_comb.msg.cp = ^header_comb.raw[61:0]; 

end
            
        
         
  always_ff @(posedge clk, negedge rst_n) begin : seq_part
    if (!rst_n) begin
      ltsm_vld <= 1'b0;
      header_reg <= '0;
      payload <= '0;
    end else if (ltsm_valid_send && push_rdy) begin
      ltsm_vld <= 1'b1;
      header_reg <= header_comb;
      payload <= ltsm_msg_data_send;
    end else begin
      ltsm_vld <= 1'b0;
    end
  end

    assign ltsm_msg = {payload, header_reg}; 

endmodule