package msg_codec_pkg;
    import UCIe_pkg::*;
    import sb_pkg::*;
/*
    function automatic sb_header_u encode_rdi_header(
        input sb_rdi_msg_no_e msg_no,
        input logic stall
    );
        
        sb_header_u hdr;
        hdr        = '0;
        hdr.msg.opcode = SB_MSG_WITHOUT_DATA;
        hdr.msg.srcid  = PHY;
        hdr.msg.dstid  = REMOTE_PHY;
        hdr.msg.dp     = 1'b0;
        // msgcode
        case (msg_no)
            ACTIVE_REQ: begin
                hdr.msg.msgcode = msg_code_e'(8'h01);
                hdr.msg.MsgSubcode = 8'h01;
                hdr.msg.MsgInfo = 16'h0000;
            end
            L1_REQ: begin
                hdr.msg.msgcode = msg_code_e'(8'h01);
                hdr.msg.MsgSubcode = 8'h04;
                hdr.msg.MsgInfo = 16'h0000;
            end
            L2_REQ: begin
                hdr.msg.msgcode = msg_code_e'(8'h01);
                hdr.msg.MsgSubcode = 8'h08;
                hdr.msg.MsgInfo = 16'h0000;
            end
            LINK_RESET_REQ: begin
                hdr.msg.msgcode = msg_code_e'(8'h01);
                hdr.msg.MsgSubcode = 8'h09;
                hdr.msg.MsgInfo = 16'h0000;
            end
            LINK_ERROR_REQ: begin
                hdr.msg.msgcode = msg_code_e'(8'h01);
                hdr.msg.MsgSubcode = 8'h0A;
                hdr.msg.MsgInfo = 16'h0000;
            end
            RETRAIN_REQ: begin
                hdr.msg.msgcode = msg_code_e'(8'h01);
                hdr.msg.MsgSubcode = 8'h0B;
                hdr.msg.MsgInfo = 16'h0000;
            end
            DISABLE_REQ: begin
                hdr.msg.msgcode = msg_code_e'(8'h01);
                hdr.msg.MsgSubcode = 8'h0C;
                hdr.msg.MsgInfo = 16'h0000;
            end
            ACTIVE_RSP: begin
                hdr.msg.msgcode = msg_code_e'(8'h02);
                hdr.msg.MsgSubcode = 8'h01;
                hdr.msg.MsgInfo = stall ? 16'hFFFF : 16'h0000;
            end
            PMNAK_RSP: begin
                hdr.msg.msgcode = msg_code_e'(8'h02);
                hdr.msg.MsgSubcode = 8'h02;
                hdr.msg.MsgInfo = stall ? 16'hFFFF : 16'h0000;
            end
            L1_RSP: begin
                hdr.msg.msgcode = msg_code_e'(8'h02);
                hdr.msg.MsgSubcode = 8'h04;
                hdr.msg.MsgInfo = stall ? 16'hFFFF : 16'h0000;
            end
            L2_RSP: begin
                hdr.msg.msgcode = msg_code_e'(8'h02);
                hdr.msg.MsgSubcode = 8'h08;
                hdr.msg.MsgInfo = stall ? 16'hFFFF : 16'h0000;
            end
            LINK_RESET_RSP: begin
                hdr.msg.msgcode = msg_code_e'(8'h02);
                hdr.msg.MsgSubcode = 8'h09;
                hdr.msg.MsgInfo = stall ? 16'hFFFF : 16'h0000;
            end
            LINK_ERROR_RSP: begin
                hdr.msg.msgcode = msg_code_e'(8'h02);
                hdr.msg.MsgSubcode = 8'h0A;
                hdr.msg.MsgInfo = stall ? 16'hFFFF : 16'h0000;
            end
            RETRAIN_RSP: begin
                hdr.msg.msgcode = msg_code_e'(8'h02);
                hdr.msg.MsgSubcode = 8'h0B;
                hdr.msg.MsgInfo = stall ? 16'hFFFF : 16'h0000;
            end
            DISABLE_RSP: begin
                hdr.msg.msgcode = msg_code_e'(8'h02);
                hdr.msg.MsgSubcode = 8'h0C;
                hdr.msg.MsgInfo = stall ? 16'hFFFF : 16'h0000;
            end
            default: begin
                hdr.msg.msgcode = msg_code_e'(8'h00);
                hdr.msg.MsgSubcode = 8'h00;
                hdr.msg.MsgInfo = 16'h0000;
            end
        endcase
        hdr.msg.cp = ^hdr.raw[61:0];

        return hdr;
    endfunction
 */

    function automatic sb_header_u encode_msg_header(
        input msg_no_e       msg_no,
        input logic [15:0]   msg_info,
        input logic [63:0]   data,
        input logic          stall
    );

      sb_header_u hdr;
      logic has_data;

      hdr      = '0;
      has_data = 1'b0;

      hdr.msg.srcid   = PHY;
      hdr.msg.dstid   = REMOTE_PHY;
      hdr.msg.MsgInfo = msg_info;

      case (msg_no)

      // ==================================================
      // SBINIT
      // ==================================================
      SBINIT_Out_of_Reset: begin
          hdr.msg.msgcode    = SBINIT_OFFRESET_DOMAIN;
          hdr.msg.MsgSubcode = 8'h00;
      end

      SBINIT_done_req: begin
          hdr.msg.msgcode    = SBINIT_REQ_DOMAIN;
          hdr.msg.MsgSubcode = 8'h01;
      end

      SBINIT_done_resp: begin
          hdr.msg.msgcode    = SBINIT_RESP_DOMAIN;
          hdr.msg.MsgSubcode = 8'h01;
      end

      // ==================================================
      // RDI
      // ==================================================
      RDI_ACTIVE_REQ:      begin hdr.msg.msgcode = RDI_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h01; end
      RDI_ACTIVE_RSP:      begin hdr.msg.msgcode = RDI_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h01; end
      RDI_L1_REQ:          begin hdr.msg.msgcode = RDI_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h04; end
      RDI_L1_RSP:          begin hdr.msg.msgcode = RDI_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h04; end
      RDI_L2_REQ:          begin hdr.msg.msgcode = RDI_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h08; end
      RDI_L2_RSP:          begin hdr.msg.msgcode = RDI_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h08; end
      RDI_LINK_RESET_REQ:  begin hdr.msg.msgcode = RDI_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h09; end
      RDI_LINK_RESET_RSP:  begin hdr.msg.msgcode = RDI_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h09; end
      RDI_LINK_ERROR_REQ:  begin hdr.msg.msgcode = RDI_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h0A; end
      RDI_LINK_ERROR_RSP:  begin hdr.msg.msgcode = RDI_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h0A; end
      RDI_RETRAIN_REQ:     begin hdr.msg.msgcode = RDI_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h0B; end
      RDI_RETRAIN_RSP:     begin hdr.msg.msgcode = RDI_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h0B; end
      RDI_DISABLE_REQ:     begin hdr.msg.msgcode = RDI_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h0C; end
      RDI_DISABLE_RSP:     begin hdr.msg.msgcode = RDI_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h0C; end
      RDI_PMNAK_RSP:       begin hdr.msg.msgcode = RDI_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h02; end

      // ==================================================
      // MBINIT PARAM
      // ==================================================
      MBINIT_PARAM_configuration_req:  begin hdr.msg.msgcode = MBINIT_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h00; has_data = 1; end
      MBINIT_PARAM_configuration_resp: begin hdr.msg.msgcode = MBINIT_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h00; has_data = 1; end
      MBINIT_PARAM_SBFE_req:           begin hdr.msg.msgcode = MBINIT_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h01; has_data = 1; end
      MBINIT_PARAM_SBFE_resp:          begin hdr.msg.msgcode = MBINIT_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h01; has_data = 1; end
      MBINIT_CAL_Done_req:             begin hdr.msg.msgcode = MBINIT_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h02; end
      MBINIT_CAL_Done_resp:            begin hdr.msg.msgcode = MBINIT_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h02; end

      // ==================================================
      // MBINIT REPAIRCLK
      // ==================================================
      MBINIT_REPAIRCLK_init_req:    begin hdr.msg.msgcode = MBINIT_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h03; end
      MBINIT_REPAIRCLK_init_resp:   begin hdr.msg.msgcode = MBINIT_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h03; end
      MBINIT_REPAIRCLK_result_req:  begin hdr.msg.msgcode = MBINIT_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h04; end
      MBINIT_REPAIRCLK_result_resp: begin hdr.msg.msgcode = MBINIT_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h04; end
      MBINIT_REPAIRCLK_done_req:    begin hdr.msg.msgcode = MBINIT_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h08; end
      MBINIT_REPAIRCLK_done_resp:   begin hdr.msg.msgcode = MBINIT_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h08; end

      // ==================================================
      // MBINIT REPAIRVAL
      // ==================================================
      MBINIT_REPAIRVAL_init_req:    begin hdr.msg.msgcode = MBINIT_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h09; end
      MBINIT_REPAIRVAL_init_resp:   begin hdr.msg.msgcode = MBINIT_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h09; end
      MBINIT_REPAIRVAL_result_req:  begin hdr.msg.msgcode = MBINIT_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h0A; end
      MBINIT_REPAIRVAL_result_resp: begin hdr.msg.msgcode = MBINIT_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h0A; end
      MBINIT_REPAIRVAL_done_req:    begin hdr.msg.msgcode = MBINIT_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h0C; end
      MBINIT_REPAIRVAL_done_resp:   begin hdr.msg.msgcode = MBINIT_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h0C; end

      // ---------------- REVERSALMB ----------------

      MBINIT_REVERSALMB_init_req:  begin hdr.msg.msgcode = MBINIT_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h0D; end
      MBINIT_REVERSALMB_init_resp: begin hdr.msg.msgcode = MBINIT_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h0D; end

      MBINIT_REVERSALMB_clear_error_req:  begin hdr.msg.msgcode = MBINIT_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h0E; end
      MBINIT_REVERSALMB_clear_error_resp: begin hdr.msg.msgcode = MBINIT_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h0E; end

      MBINIT_REVERSALMB_result_req:  begin hdr.msg.msgcode = MBINIT_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h0F; end
      MBINIT_REVERSALMB_result_resp: begin hdr.msg.msgcode = MBINIT_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h0F; has_data = 1; end

      MBINIT_REVERSALMB_done_req:  begin hdr.msg.msgcode = MBINIT_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h10; end
      MBINIT_REVERSALMB_done_resp: begin hdr.msg.msgcode = MBINIT_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h10; end


      // ---------------- REPAIRMB ----------------

      MBINIT_REPAIRMB_start_req:  begin hdr.msg.msgcode = MBINIT_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h11; end
      MBINIT_REPAIRMB_start_resp: begin hdr.msg.msgcode = MBINIT_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h11; end

      MBINIT_REPAIRMB_apply_repair_req:  begin hdr.msg.msgcode = MBINIT_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h12; has_data = 1; end
      MBINIT_REPAIRMB_apply_repair_resp: begin hdr.msg.msgcode = MBINIT_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h12; end

      MBINIT_REPAIRMB_end_req:  begin hdr.msg.msgcode = MBINIT_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h13; end
      MBINIT_REPAIRMB_end_resp: begin hdr.msg.msgcode = MBINIT_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h13; end

      MBINIT_REPAIRMB_apply_degrade_req:  begin hdr.msg.msgcode = MBINIT_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h14; end
      MBINIT_REPAIRMB_apply_degrade_resp: begin hdr.msg.msgcode = MBINIT_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h14; end

      // ==================================================
      // MBTRAIN
      // ==================================================
      MBTRAIN_VALVREF_start_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h00; end
      MBTRAIN_VALVREF_start_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h00; end

      MBTRAIN_VALVREF_end_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h01; end
      MBTRAIN_VALVREF_end_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h01; end

      MBTRAIN_DATAVREF_start_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h02; end
      MBTRAIN_DATAVREF_start_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h02; end

      MBTRAIN_DATAVREF_end_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h03; end
      MBTRAIN_DATAVREF_end_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h03; end

      MBTRAIN_SPEEDIDLE_done_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h04; end
      MBTRAIN_SPEEDIDLE_done_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h04; end

      MBTRAIN_TXSELFCAL_Done_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h05; end
      MBTRAIN_TXSELFCAL_Done_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h05; end

      MBTRAIN_RXCLKCAL_start_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h06; end
      MBTRAIN_RXCLKCAL_start_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h06; end

      MBTRAIN_RXCLKCAL_done_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h07; end
      MBTRAIN_RXCLKCAL_done_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h07; end

      MBTRAIN_VALTRAINCENTER_start_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h08; end
      MBTRAIN_VALTRAINCENTER_start_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h08; end

      MBTRAIN_VALTRAINCENTER_done_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h09; end
      MBTRAIN_VALTRAINCENTER_done_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h09; end

      MBTRAIN_VALTRAINVREF_start_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h0A; end
      MBTRAIN_VALTRAINVREF_start_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h0A; end

      MBTRAIN_VALTRAINVREF_end_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h0B; end
      MBTRAIN_VALTRAINVREF_end_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h0B; end

      MBTRAIN_DATATRAINCENTER1_start_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h0C; end
      MBTRAIN_DATATRAINCENTER1_start_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h0C; end

      MBTRAIN_DATATRAINCENTER1_end_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h0D; end
      MBTRAIN_DATATRAINCENTER1_end_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h0D; end

      MBTRAIN_DATATRAINVREF_start_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h0E; end
      MBTRAIN_DATATRAINVREF_start_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h0E; end

      MBTRAIN_DATATRAINVREF_end_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h10; end
      MBTRAIN_DATATRAINVREF_end_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h10; end

      MBTRAIN_RXDESKEW_start_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h11; end
      MBTRAIN_RXDESKEW_start_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h11; end

      MBTRAIN_RXDESKEW_end_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h12; end
      MBTRAIN_RXDESKEW_end_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h12; end

      MBTRAIN_DATATRAINCENTER2_start_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h13; end
      MBTRAIN_DATATRAINCENTER2_start_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h13; end

      MBTRAIN_DATATRAINCENTER2_end_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h14; end
      MBTRAIN_DATATRAINCENTER2_end_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h14; end

      MBTRAIN_LINKSPEED_start_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h15; end
      MBTRAIN_LINKSPEED_start_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h15; end

      MBTRAIN_LINKSPEED_error_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h16; end
      MBTRAIN_LINKSPEED_error_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h16; end

      MBTRAIN_LINKSPEED_exit_to_repair_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h17; end
      MBTRAIN_LINKSPEED_exit_to_repair_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h17; end

      MBTRAIN_LINKSPEED_exit_to_speed_degrade_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h18; end
      MBTRAIN_LINKSPEED_exit_to_speed_degrade_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h18; end

      MBTRAIN_LINKSPEED_done_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h19; end
      MBTRAIN_LINKSPEED_done_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h19; end

      MBTRAIN_REPAIR_init_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h1B; end
      MBTRAIN_REPAIR_init_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h1B; end

      MBTRAIN_REPAIR_apply_repair_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h1C; has_data = 1; end
      MBTRAIN_REPAIR_apply_repair_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h1C; end

      MBTRAIN_REPAIR_end_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h1D; end
      MBTRAIN_REPAIR_end_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h1D; end

      MBTRAIN_REPAIR_apply_degrade_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h1E; end
      MBTRAIN_REPAIR_apply_degrade_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h1E; end

      MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h1F; end
      MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h1F; end

      MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h20; end
      MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h20; end

      MBTRAIN_RXCLKCAL_TCKN_L_shift_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h21; end
      MBTRAIN_RXCLKCAL_TCKN_L_shift_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h21; end

      RECAL_track_tx_adjust_req:  begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h22; end
      RECAL_track_tx_adjust_resp: begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h22; end

      // ==================================================
      // RECAL
      // ==================================================
      RECAL_track_pattern_init_req:  begin hdr.msg.msgcode = RECAL_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h00; end
      RECAL_track_pattern_init_resp: begin hdr.msg.msgcode = RECAL_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h00; end
      RECAL_track_pattern_done_req:  begin hdr.msg.msgcode = RECAL_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h01; end
      RECAL_track_pattern_done_resp: begin hdr.msg.msgcode = RECAL_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h01; end
      RECAL_track_tx_adjust_req:     begin hdr.msg.msgcode = MBTRAIN_REQ_DOMAIN; hdr.msg.MsgSubcode = 8'h22; end
      RECAL_track_tx_adjust_resp:    begin hdr.msg.msgcode = MBTRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h22; end

      // ==================================================
      // PHYRETRAIN
      // ==================================================
      PHYRETRAIN_retrain_start_req:  begin hdr.msg.msgcode = PHYRETRAIN_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h01; end
      PHYRETRAIN_retrain_start_resp: begin hdr.msg.msgcode = PHYRETRAIN_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h01; end

      // ==================================================
      // TRAINERROR
      // ==================================================
      TRAINERROR_Entry_req:  begin hdr.msg.msgcode = TRAINERROR_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h00; end
      TRAINERROR_Entry_resp: begin hdr.msg.msgcode = TRAINERROR_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h00; end

      // ==================================================
      // TEST DOMAIN
      // ==================================================

      // ---------- Tx Init D2C ----------

      Start_Tx_Init_D_to_C_point_test_req:  begin hdr.msg.msgcode = TEST_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h01; has_data = 1; end
      Start_Tx_Init_D_to_C_point_test_resp: begin hdr.msg.msgcode = TEST_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h01; end

      LFSR_clear_error_req:  begin hdr.msg.msgcode = TEST_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h02; end
      LFSR_clear_error_resp: begin hdr.msg.msgcode = TEST_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h02; end

      Tx_Init_D_to_C_results_req:  begin hdr.msg.msgcode = TEST_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h03; end
      Tx_Init_D_to_C_results_resp: begin hdr.msg.msgcode = TEST_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h03; has_data = 1; end

      End_Tx_Init_D_to_C_point_test_req:  begin hdr.msg.msgcode = TEST_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h04; end
      End_Tx_Init_D_to_C_point_test_resp: begin hdr.msg.msgcode = TEST_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h04; end

      Start_Tx_Init_D_to_C_eye_sweep_req:  begin hdr.msg.msgcode = TEST_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h05; has_data = 1; end
      Start_Tx_Init_D_to_C_eye_sweep_resp: begin hdr.msg.msgcode = TEST_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h05; end

      End_Tx_Init_D_to_C_eye_sweep_req:  begin hdr.msg.msgcode = TEST_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h06; end
      End_Tx_Init_D_to_C_eye_sweep_resp: begin hdr.msg.msgcode = TEST_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h06; end


      // ---------- Rx Init D2C ----------

      Start_Rx_Init_D_to_C_point_test_req:  begin hdr.msg.msgcode = TEST_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h07; has_data = 1; end
      Start_Rx_Init_D_to_C_point_test_resp: begin hdr.msg.msgcode = TEST_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h07; end

      Rx_Init_D_to_C_Tx_Count_Done_req:  begin hdr.msg.msgcode = TEST_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h08; end
      Rx_Init_D_to_C_Tx_Count_Done_resp: begin hdr.msg.msgcode = TEST_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h08; end

      End_Rx_Init_D_to_C_point_test_req:  begin hdr.msg.msgcode = TEST_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h09; end
      End_Rx_Init_D_to_C_point_test_resp: begin hdr.msg.msgcode = TEST_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h09; end

      Start_Rx_Init_D_to_C_eye_sweep_req:  begin hdr.msg.msgcode = TEST_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h0A; has_data = 1; end
      Start_Rx_Init_D_to_C_eye_sweep_resp: begin hdr.msg.msgcode = TEST_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h0A; end

      Rx_Init_D_to_C_results_req:  begin hdr.msg.msgcode = TEST_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h0B; end
      Rx_Init_D_to_C_results_resp: begin hdr.msg.msgcode = TEST_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h0B; has_data = 1; end

      Rx_Init_D_to_C_sweep_done_with_results: begin
          hdr.msg.msgcode    = RX_TEST_SWEEP_DONE_RESULT;
          hdr.msg.MsgSubcode = 8'h0C;
          has_data       = 1;
      end

      End_Rx_Init_D_to_C_eye_sweep_req:  begin hdr.msg.msgcode = TEST_REQ_DOMAIN;  hdr.msg.MsgSubcode = 8'h0D; end
      End_Rx_Init_D_to_C_eye_sweep_resp: begin hdr.msg.msgcode = TEST_RESP_DOMAIN; hdr.msg.MsgSubcode = 8'h0D; end

      // ==================================================
      // DEFAULT
      // ==================================================
      default: begin
          hdr.msg.msgcode    = msg_code_e'(8'h00);
          hdr.msg.MsgSubcode = 8'h00;
      end

      endcase


    if ((msg_no >= RDI_ACTIVE_REQ && 
      msg_no <= RDI_PMNAK_RSP && 
      msg_no != NOP))begin
        if(stall) begin
            hdr.msg.MsgInfo = 16'hFFFF;
        end
        else begin
            hdr.msg.MsgInfo = 16'h0000;
        end
    end
    else hdr.msg.MsgInfo = msg_info;

      hdr.msg.opcode = has_data ? SB_MSG_WITH_64_DATA
                            : SB_MSG_WITHOUT_DATA;

      hdr.msg.dp = has_data ? ^data : 1'b0;

      hdr.msg.cp = ^hdr.raw[61:0];

      return hdr;

    endfunction


endpackage