`timescale 1ns/1ps


class mbtrain_cb_monitor;
    virtual mbtrain_cb_if vif;
    mbtrain_cb_config cfg;

    function new(virtual mbtrain_cb_if vif, mbtrain_cb_config cfg);
        this.vif = vif;
        this.cfg = cfg;
    endfunction

    task run();
        state_n_e prev_substate;
        logic [2:0] prev_tx_mask;
        logic [2:0] prev_rx_mask;
        bit prev_sweep_active;
        bit prev_sweep_done;

        prev_substate = LOG_NOP;
        prev_tx_mask = 3'b000;
        prev_rx_mask = 3'b000;
        prev_sweep_active = 1'b0;
        prev_sweep_done = 1'b0;

        forever begin
            @(posedge vif.lclk);

            // Substate change
            if (vif.current_mbtrain_substate != prev_substate) begin
                state_n_e tmp_state = vif.current_mbtrain_substate;
                if (cfg.enable_verbose) begin
                    $display("[%0t] [MON] MBTRAIN Substate changed: %s -> %s", $time, prev_substate.name(), tmp_state.name());
                end
                prev_substate = vif.current_mbtrain_substate;
            end

            // Sideband TX
            if (cfg.enable_verbose && vif.substate_tx_sb_msg_valid) begin
                msg_no_e tmp_tx = msg_no_e'(vif.substate_tx_sb_msg);
                $display("[%0t] [MON] SB TX Event: msg=%s, info=0x%h, data=0x%h", $time, tmp_tx.name(), vif.substate_tx_msginfo, vif.substate_tx_data_field);
            end

            // Sideband RX
            if (cfg.enable_verbose && vif.rx_sb_msg_valid) begin
                msg_no_e tmp_rx = msg_no_e'(vif.rx_sb_msg);
                $display("[%0t] [MON] SB RX Event: msg=%s, info=0x%h, data=0x%h", $time, tmp_rx.name(), vif.rx_msginfo, 64'h0);
            end

            // LTSM Requests
            if (vif.ltsm_linkinit_req)   $display("[%0t] [MON] LTSM LinkInit Req detected in %s", $time, vif.current_mbtrain_substate.name());
            if (vif.ltsm_phyretrain_req) $display("[%0t] [MON] LTSM PhyRetrain Req detected in %s", $time, vif.current_mbtrain_substate.name());
            if (vif.ltsm_trainerror_req) $display("[%0t] [MON] LTSM TrainError Req detected in %s", $time, vif.current_mbtrain_substate.name());

            // Lane Mask
            if (vif.mb_tx_data_lane_mask != prev_tx_mask) begin
                $display("[%0t] [MON] TX Lane Mask changed to: %b", $time, vif.mb_tx_data_lane_mask);
                prev_tx_mask = vif.mb_tx_data_lane_mask;
            end
            if (vif.mb_rx_data_lane_mask != prev_rx_mask) begin
                $display("[%0t] [MON] RX Lane Mask changed to: %b", $time, vif.mb_rx_data_lane_mask);
                prev_rx_mask = vif.mb_rx_data_lane_mask;
            end

            // D2C Sweep
            if ((vif.local_sweep_en || vif.partner_sweep_en) && !prev_sweep_active) begin
                $display("[%0t] [MON] D2C Sweep Started: local=%b, partner=%b", $time, vif.local_sweep_en, vif.partner_sweep_en);
            end
            if (vif.sweep_done && !prev_sweep_done && prev_sweep_active) begin
                $display("[%0t] [MON] D2C Sweep Done: pass=%h", $time, vif.d2c_perlane_pass);
            end
            prev_sweep_active = vif.local_sweep_en || vif.partner_sweep_en;
            prev_sweep_done = vif.sweep_done;
        end
    endtask

endclass
