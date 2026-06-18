`timescale 1ns/1ps


class mbtrain_cb_coverage;
    virtual mbtrain_cb_if vif;

    int rxdeskew_loop_count = 0;
    logic [3:0] current_width;
    logic [2:0] current_speed;
    logic [7:0] current_tx_msg;
    state_n_e   current_substate;
    bit         repair_success;
    bit         repair_fail;
    
    covergroup cg_width;
        cp_width: coverpoint current_width {
            bins x16 = {2};
            bins x8  = {1};
            bins x4  = {3}; 
        }
    endgroup

    covergroup cg_speed;
        cp_speed: coverpoint current_speed {
            bins speed_0 = {0};
            bins speed_1 = {1};
            bins speed_2 = {2};
            bins speed_3 = {3};
            bins speed_4 = {4};
            bins speed_5 = {5};
            bins speed_6 = {6};
            bins speed_7 = {7};
        }
    endgroup

    covergroup cg_linkspeed_route;
        cp_route: coverpoint current_tx_msg {
            bins done = {MBTRAIN_LINKSPEED_done_req};
            bins error = {MBTRAIN_LINKSPEED_error_req};
            bins exit_repair = {MBTRAIN_LINKSPEED_exit_to_repair_req};
            bins exit_speed_degrade = {MBTRAIN_LINKSPEED_exit_to_speed_degrade_req};
            bins exit_phy_retrain = {MBTRAIN_LINKSPEED_exit_to_phy_retrain_OR_MBTRAIN_RXDESKEW_EQ_Preset_req};
        }
    endgroup

    covergroup cg_rxdeskew_loops;
        cp_loops: coverpoint rxdeskew_loop_count {
            bins loop_0 = {0};
            bins loop_1 = {1};
            bins loop_2 = {2};
            bins loop_3 = {3};
            bins loop_4 = {4};
            bins overflow = {[5:$]};
        }
    endgroup

    covergroup cg_repair_result;
        cp_success: coverpoint repair_success {
            bins pass = {1};
        }
        cp_fail: coverpoint repair_fail {
            bins fail = {1};
        }
    endgroup

    function new(virtual mbtrain_cb_if vif);
        this.vif = vif;
        cg_width = new();
        cg_speed = new();
        cg_linkspeed_route = new();
        cg_rxdeskew_loops = new();
        cg_repair_result = new();
    endfunction

    task run();
        state_n_e past_substate = LOG_NOP;
        forever begin
            @(posedge vif.lclk);
            
            current_width = vif.rf_ctrl_target_link_width;
            current_speed = vif.phy_negotiated_speed;
            current_tx_msg = vif.substate_tx_sb_msg;
            current_substate = vif.current_mbtrain_substate;
            
            cg_width.sample();
            cg_speed.sample();

            if (vif.substate_tx_sb_msg_valid) begin
                if (current_substate == LOG_MBTRAIN_LINKSPEED) begin
                    cg_linkspeed_route.sample();
                end
            end

            // Track RXDESKEW loops (loopback exit to DTC1)
            if (vif.substate_tx_sb_msg_valid && 
                vif.substate_tx_sb_msg == MBTRAIN_RXDESKEW_exit_to_DATATRAINCENTER1_req && 
                current_substate == LOG_MBTRAIN_RXDESKEW) begin
                rxdeskew_loop_count++;
                cg_rxdeskew_loops.sample();
            end
            
            // Reset loop count when entering RXDESKEW from another state
            if (current_substate == LOG_MBTRAIN_RXDESKEW && past_substate != LOG_MBTRAIN_RXDESKEW && past_substate != LOG_MBTRAIN_DATATRAINCENTER1) begin
                rxdeskew_loop_count = 0;
            end

            if (past_substate == LOG_MBTRAIN_REPAIR && current_substate != LOG_MBTRAIN_REPAIR) begin
                repair_success = !vif.ltsm_trainerror_req;
                repair_fail    = vif.ltsm_trainerror_req;
                cg_repair_result.sample();
            end
            
            past_substate = current_substate;
        end
    endtask

endclass
