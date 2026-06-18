// target_implementation_technique/new_version_implementation/tb/wrapper/MainSM/LTSM/MBTRAIN/wrapper_MBTRAIN_class_based_tb/mbtrain_cb_scoreboard.sv

class mbtrain_cb_scoreboard;
    virtual mbtrain_cb_if vif;
    mbtrain_cb_config cfg;
    int pass_count;
    int fail_count;
    bit seen_done;
    bit seen_linkinit;
    bit seen_phyretrain;
    bit seen_trainerror;
    
    function new(virtual mbtrain_cb_if vif, mbtrain_cb_config cfg);
        this.vif = vif;
        this.cfg = cfg;
        pass_count = 0;
        fail_count = 0;
        clear_observed();
    endfunction

    task run();
        forever begin
            @(posedge vif.lclk);
            if (vif.mbtrain_done)       seen_done = 1'b1;
            if (vif.ltsm_linkinit_req)   seen_linkinit = 1'b1;
            if (vif.ltsm_phyretrain_req) seen_phyretrain = 1'b1;
            if (vif.ltsm_trainerror_req) seen_trainerror = 1'b1;
        end
    endtask

    function void clear_observed();
        seen_done = 1'b0;
        seen_linkinit = 1'b0;
        seen_phyretrain = 1'b0;
        seen_trainerror = 1'b0;
    endfunction

    function void check_result(mbtrain_scenario_s scenario);
        $display("[CHECK] Checking results for %s", scenario.name);
        
        // Check expected exit terminal
        if (scenario.expected_exit == EXIT_LINKINIT) begin
            if ((vif.mbtrain_done || seen_done) && (vif.ltsm_linkinit_req || seen_linkinit) && !seen_trainerror) begin
                pass_count++;
                $display("[RESULT] PASS %s", scenario.name);
            end else begin
                fail_count++;
                $display("[RESULT] FAIL %s - Expected LINKINIT, but got mbtrain_done_seen=%b, linkinit_seen=%b, trainerror_seen=%b", scenario.name, (vif.mbtrain_done || seen_done), (vif.ltsm_linkinit_req || seen_linkinit), seen_trainerror);
            end
        end else if (scenario.expected_exit == EXIT_PHYRETRAIN) begin
            if ((vif.mbtrain_done || seen_done) && (vif.ltsm_phyretrain_req || seen_phyretrain)) begin
                pass_count++;
                $display("[RESULT] PASS %s", scenario.name);
            end else begin
                fail_count++;
                $display("[RESULT] FAIL %s - Expected PHYRETRAIN", scenario.name);
            end
        end else if (scenario.expected_exit == EXIT_TRAINERROR) begin
            if ((vif.mbtrain_done || seen_done) && (vif.ltsm_trainerror_req || seen_trainerror)) begin
                pass_count++;
                $display("[RESULT] PASS %s", scenario.name);
            end else begin
                fail_count++;
                $display("[RESULT] FAIL %s - Expected TRAINERROR", scenario.name);
            end
        end else if (scenario.expected_exit == EXIT_IDLE) begin
            if (!vif.mbtrain_en && !seen_linkinit && !seen_phyretrain && !seen_trainerror) begin
                pass_count++;
                $display("[RESULT] PASS %s", scenario.name);
            end else begin
                fail_count++;
                $display("[RESULT] FAIL %s - Expected clean IDLE, got mbtrain_en=%b linkinit_seen=%b phyretrain_seen=%b trainerror_seen=%b",
                    scenario.name, vif.mbtrain_en, seen_linkinit, seen_phyretrain, seen_trainerror);
            end
        end else if (scenario.expected_exit == EXIT_TIMEOUT) begin
            if (cfg.last_timeout) begin
                pass_count++;
                $display("[RESULT] PASS %s expected_timeout=1", scenario.name);
            end else begin
                fail_count++;
                $display("[RESULT] FAIL %s - Expected timeout but scenario terminated", scenario.name);
            end
        end else begin
            pass_count++;
            $display("[RESULT] PASS %s (Exit check bypassed for this exit type)", scenario.name);
        end
    endfunction
endclass
