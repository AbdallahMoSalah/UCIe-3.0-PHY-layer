import sb_pkg::*;
import UCIe_pkg::*;

module LTSM_Packetizer (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [ 63:0] ltsm_msg_data_send,
    input  logic [ 15:0] ltsm_msg_info_send,
    input  logic [  7:0] ltsm_msg_no_send,
    input  logic         ltsm_valid_send,
    input  logic         push_ready,
    output logic [127:0] ltsm_msg,
    output logic         ltsm_vld,
    output logic         ltsm_ready
);


sb_header_t header_comb,header_reg;
logic [63:0] payload;


assign dp = ^ltsm_msg_data_send;
assign cp = ^header_comb[61:0]; 

    always_comb begin

    // =====================================================
    // Defaults
    // =====================================================
    header_comb             = '0;
    header_comb.dstid       = REMOTE_PHY;
    header_comb.srcid       = LOCAL_PHY;
    header_comb.dp          = dp;
    header_comb.cp          = cp;
    header_comb.MsgInfo     = ltsm_msg_info_send;

    // =====================================================
    // SBINIT DOMAIN
    // =====================================================
    if (msg_no >= SBINIT_Out_of_Reset && msg_no <= SBINIT_done_resp) begin // لو عايز تبسطها ماشي كنت عايز اخليها شبه الي تحت مش فارقه 
      if (msg_no == SBINIT_Out_of_Reset) header_comb.msgcode = SBINIT_OFFRESET_DOMAIN;
      else if (msg_no[0] == 1'b0) header_comb.msgcode = SBINIT_REQ_DOMAIN;
      else header_comb.msgcode = SBINIT_RESP_DOMAIN;
      case (msg_no)
        SBINIT_Out_of_Reset: header_comb.MsgSubcode = 8'h00;
        SBINIT_done_req:     header_comb.MsgSubcode = 8'h01;
        SBINIT_done_resp:    header_comb.MsgSubcode = 8'h02;
      endcase
    end

    

    // =====================================================
    // MBINIT DOMAIN
    // =====================================================
    else if (msg_no >= MBINIT_PARAM_configuration_req &&
             msg_no <= MBINIT_REPAIRMB_end_resp) begin

        if (msg_no[0] == 1'b0)
            header_comb.msgcode = MBINIT_REQ_DOMAIN;
        else
            header_comb.msgcode = MBINIT_RESP_DOMAIN;

        case (msg_no)

            MBINIT_PARAM_configuration_req,
            MBINIT_PARAM_configuration_resp:
                header_comb.MsgSubcode = 8'h00;

            MBINIT_PARAM_SBFE_req,
            MBINIT_PARAM_SBFE_resp:
                header_comb.MsgSubcode = 8'h01;

            MBINIT_CAL_Done_req,
            MBINIT_CAL_Done_resp:
                header_comb.MsgSubcode = 8'h02;

            // ---------------- REPAIRCLK ----------------
            MBINIT_REPAIRCLK_init_req,
            MBINIT_REPAIRCLK_init_resp:
                header_comb.MsgSubcode = 8'h03;

            MBINIT_REPAIRCLK_result_req,
            MBINIT_REPAIRCLK_result_resp:
                header_comb.MsgSubcode = 8'h04;

            MBINIT_REPAIRCLK_done_req,
            MBINIT_REPAIRCLK_done_resp:
                header_comb.MsgSubcode = 8'h08;

            // ---------------- REPAIRVAL ----------------
            MBINIT_REPAIRVAL_init_req,
            MBINIT_REPAIRVAL_init_resp:
                header_comb.MsgSubcode = 8'h09;

            MBINIT_REPAIRVAL_result_req,
            MBINIT_REPAIRVAL_result_resp:
                header_comb.MsgSubcode = 8'h0A;

            MBINIT_REPAIRVAL_done_req,
            MBINIT_REPAIRVAL_done_resp:
                header_comb.MsgSubcode = 8'h0C;

            // ---------------- REVERSALMB ----------------
            MBINIT_REVERSALMB_init_req,
            MBINIT_REVERSALMB_init_resp:
                header_comb.MsgSubcode = 8'h0D;

            MBINIT_REVERSALMB_clear_error_req,
            MBINIT_REVERSALMB_clear_error_resp:
                header_comb.MsgSubcode = 8'h0E;

            MBINIT_REVERSALMB_result_req,
            MBINIT_REVERSALMB_result_resp:
                header_comb.MsgSubcode = 8'h0F;

            MBINIT_REVERSALMB_done_req,
            MBINIT_REVERSALMB_done_resp:
                header_comb.MsgSubcode = 8'h10;

            // ---------------- REPAIRMB ----------------
            MBINIT_REPAIRMB_start_req,
            MBINIT_REPAIRMB_start_resp:
                header_comb.MsgSubcode = 8'h11;

            MBINIT_REPAIRMB_apply_degrade_req,
            MBINIT_REPAIRMB_apply_degrade_resp:
                header_comb.MsgSubcode = 8'h12;

            MBINIT_REPAIRMB_end_req,
            MBINIT_REPAIRMB_end_resp:
                header_comb.MsgSubcode = 8'h13;

        endcase
    end


    // =====================================================
    // MBTRAIN DOMAIN (B5 / BA)
    // includes RECAL_track_tx_adjust
    // =====================================================
    else if ( (msg_no >= MBTRAIN_VALVREF_start_req &&
               msg_no <= MBTRAIN_REPAIR_end_resp)
              ||
              (msg_no == RECAL_track_tx_adjust_req)
              ||
              (msg_no == RECAL_track_tx_adjust_resp)
            ) begin

        if (msg_no[0] == 1'b0)
            header_comb.msgcode = MBTRAIN_REQ_DOMAIN;
        else
            header_comb.msgcode = MBTRAIN_RESP_DOMAIN;

        case (msg_no)

            // ---------- VALVREF ----------
            MBTRAIN_VALVREF_start_req,
            MBTRAIN_VALVREF_start_resp:
                header_comb.MsgSubcode = 8'h00;

            MBTRAIN_VALVREF_end_req,
            MBTRAIN_VALVREF_end_resp:
                header_comb.MsgSubcode = 8'h01;

            // ---------- DATAVREF ----------
            MBTRAIN_DATAVREF_start_req,
            MBTRAIN_DATAVREF_start_resp:
                header_comb.MsgSubcode = 8'h02;

            MBTRAIN_DATAVREF_end_req,
            MBTRAIN_DATAVREF_end_resp:
                header_comb.MsgSubcode = 8'h03;

            // ---------- SPEEDIDLE ----------
            MBTRAIN_SPEEDIDLE_done_req,
            MBTRAIN_SPEEDIDLE_done_resp:
                header_comb.MsgSubcode = 8'h04;

            // ---------- TXSELFCAL ----------
            MBTRAIN_TXSELFCAL_Done_req,
            MBTRAIN_TXSELFCAL_Done_resp:
                header_comb.MsgSubcode = 8'h05;

            // ---------- RXCLKCAL ----------
            MBTRAIN_RXCLKCAL_start_req,
            MBTRAIN_RXCLKCAL_start_resp:
                header_comb.MsgSubcode = 8'h06;

            MBTRAIN_RXCLKCAL_done_req,
            MBTRAIN_RXCLKCAL_done_resp:
                header_comb.MsgSubcode = 8'h07;

            MBTRAIN_RXCLKCAL_TCKN_L_shift_req,
            MBTRAIN_RXCLKCAL_TCKN_L_shift_resp:
                header_comb.MsgSubcode = 8'h21;
            // ---------- VALTRAINCENTER ----------
            MBTRAIN_VALTRAINCENTER_start_req,
            MBTRAIN_VALTRAINCENTER_start_resp:
                header_comb.MsgSubcode = 8'h08;

            MBTRAIN_VALTRAINCENTER_done_req,
            MBTRAIN_VALTRAINCENTER_done_resp:
                header_comb.MsgSubcode = 8'h09;

            // ---------- VALTRAINVREF ----------
            MBTRAIN_VALTRAINVREF_start_req,
            MBTRAIN_VALTRAINVREF_start_resp:
                header_comb.MsgSubcode = 8'h0A;

            MBTRAIN_VALTRAINVREF_end_req,
            MBTRAIN_VALTRAINVREF_end_resp:
                header_comb.MsgSubcode = 8'h0B;

            // ---------- DATATRAINCENTER1 ----------
            MBTRAIN_DATATRAINCENTER1_start_req,
            MBTRAIN_DATATRAINCENTER1_start_resp:
                header_comb.MsgSubcode = 8'h0C;

            MBTRAIN_DATATRAINCENTER1_end_req,
            MBTRAIN_DATATRAINCENTER1_end_resp:
                header_comb.MsgSubcode = 8'h0D;

            // ---------- DATATRAINVREF ----------
            MBTRAIN_DATATRAINVREF_start_req,
            MBTRAIN_DATATRAINVREF_start_resp:
                header_comb.MsgSubcode = 8'h0E;

            MBTRAIN_DATATRAINVREF_end_req,
            MBTRAIN_DATATRAINVREF_end_resp:
                header_comb.MsgSubcode = 8'h10;

            // ---------- RXDESKEW ----------
            MBTRAIN_RXDESKEW_start_req,
            MBTRAIN_RXDESKEW_start_resp:
                header_comb.MsgSubcode = 8'h11;

            MBTRAIN_RXDESKEW_end_req,
            MBTRAIN_RXDESKEW_end_resp:
                header_comb.MsgSubcode = 8'h12;
            
            MBTRAIN_RXDESKEW_EQ_Preset_req,                  // d71
            MBTRAIN_RXDESKEW_EQ_Preset_resp:
                header_comb.MsgSubcode = 8'h1F;

            MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req,
            MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp:
                header_comb.MsgSubcode = 8'h20;


            // ---------- DATATRAINCENTER2 ----------
            MBTRAIN_DATATRAINCENTER2_start_req,
            MBTRAIN_DATATRAINCENTER2_start_resp:
                header_comb.MsgSubcode = 8'h13;

            MBTRAIN_DATATRAINCENTER2_end_req,
            MBTRAIN_DATATRAINCENTER2_end_resp:
                header_comb.MsgSubcode = 8'h14;

            // ---------- LINKSPEED ----------
            MBTRAIN_LINKSPEED_start_req,
            MBTRAIN_LINKSPEED_start_resp:
                header_comb.MsgSubcode = 8'h15;

            MBTRAIN_LINKSPEED_error_req,
            MBTRAIN_LINKSPEED_error_resp:
                header_comb.MsgSubcode = 8'h16;

            MBTRAIN_LINKSPEED_exit_to_repair_req,
            MBTRAIN_LINKSPEED_exit_to_repair_resp:
                header_comb.MsgSubcode = 8'h17;

            MBTRAIN_LINKSPEED_exit_to_speed_degrade_req,
            MBTRAIN_LINKSPEED_exit_to_speed_degrade_resp:
                header_comb.MsgSubcode = 8'h18;

            MBTRAIN_LINKSPEED_done_req,
            MBTRAIN_LINKSPEED_done_resp:
                header_comb.MsgSubcode = 8'h19;

            MBTRAIN_LINKSPEED_exit_to_phy_retrain_req,
            MBTRAIN_LINKSPEED_exit_to_phy_retrain_resp:
                header_comb.MsgSubcode = 8'h1F;

            // ---------- REPAIR ----------
            MBTRAIN_REPAIR_init_req,
            MBTRAIN_REPAIR_init_resp:
                header_comb.MsgSubcode = 8'h1B;

            MBTRAIN_REPAIR_apply_degrade_req,
            MBTRAIN_REPAIR_apply_degrade_resp:
                header_comb.MsgSubcode = 8'h1E;

            MBTRAIN_REPAIR_end_req,
            MBTRAIN_REPAIR_end_resp:
                header_comb.MsgSubcode = 8'h1D;

            // ---------- RECAL TX ADJUST ----------
            RECAL_track_tx_adjust_req,
            RECAL_track_tx_adjust_resp:
                header_comb.MsgSubcode = 8'h22;

        endcase
    end


    // =====================================================
    // RECAL PATTERN DOMAIN (D5 / DA)
    // =====================================================
    else if (msg_no == RECAL_track_pattern_init_req || //هنا مختلفه واخدها من شات فمكسل اخليها شبه الي فوق 
             msg_no == RECAL_track_pattern_init_resp) begin

        header_comb.msgcode = (msg_no[0] == 1'b0) ?
                   RECAL_REQ_DOMAIN :
                   RECAL_RESP_DOMAIN;

        header_comb.MsgSubcode = 8'h00;
    end
    else if (msg_no == RECAL_track_pattern_done_req ||
             msg_no == RECAL_track_pattern_done_resp) begin

        header_comb.msgcode = (msg_no[0] == 1'b0) ?
                   RECAL_REQ_DOMAIN :
                   RECAL_RESP_DOMAIN;

        header_comb.MsgSubcode = 8'h01;
    end


    // =====================================================
    // PHYRETRAIN
    // =====================================================
    else if (msg_no == PHYRETRAIN_retrain_start_req) begin
        header_comb.msgcode    = PHYRETRAIN_REQ_DOMAIN;
        header_comb.MsgSubcode = 8'h01;
    end
    else if (msg_no == PHYRETRAIN_retrain_start_resp) begin
        header_comb.msgcode    = PHYRETRAIN_RESP_DOMAIN;
        header_comb.MsgSubcode = 8'h01;
    end
                                                                    // دي والي تحتيها مش مستاهلين برضو بس كسلت اغيرهم ظبط بقا 

    // =====================================================
    // TRAINERROR
    // =====================================================
    else if (msg_no == TRAINERROR_Entry_req) begin
        header_comb.msgcode    = TRAINERROR_REQ_DOMAIN;
        header_comb.MsgSubcode = 8'h00;
    end
    else if (msg_no == TRAINERROR_Entry_resp) begin
        header_comb.msgcode    = TRAINERROR_RESP_DOMAIN;
        header_comb.MsgSubcode = 8'h00;
    end

end
            
        
         
  always_ff @(posedge clk, negedge rst_n) begin : seq_part
    if (!rst_n) begin
      ltsm_vld <= 1'0;
      header_reg <= '0;
      payload <= '0;
    end else if (ltsm_valid_send) begin
      ltsm_vld = 1'1;
      header_reg <= header_comb;
      payload <= ltsm_msg_data_send;
    end else begin
      ltsm_vld <= 1'0;
    end
  end

    assign ltsm_msg = {header_reg, payload}; 

endmodule
