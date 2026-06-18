// target_implementation_technique/new_version_implementation/tb/wrapper/MainSM/LTSM/MBTRAIN/wrapper_MBTRAIN_class_based_tb/mbtrain_cb_env.sv

class mbtrain_cb_env;
  mbtrain_cb_config cfg;
  mbtrain_cb_driver drv;
  mbtrain_cb_sb_agent sb_agnt;
  mbtrain_cb_d2c_model d2c;
  mbtrain_cb_monitor mon;
  mbtrain_cb_scoreboard sb;
  mbtrain_cb_coverage cov;
  virtual mbtrain_cb_if vif;

  function new(virtual mbtrain_cb_if vif);
    this.vif = vif;
    cfg = new();
    drv = new(vif, cfg);
    sb_agnt = new(vif, cfg);
    d2c = new(vif, cfg);
    mon = new(vif, cfg);
    sb = new(vif, cfg);
    cov = new(vif);
  endfunction

  task run_all(mbtrain_scenario_s scenarios[$]);
    fork
      sb_agnt.run();
      d2c.run();
      mon.run();
      sb.run();
      cov.run();
    join_none
    
    foreach(scenarios[i]) begin
      if (i != 0) begin
        $display("");
      end
      $display("--------------------------------------------------");
      sb.clear_observed();
      drv.run_scenario(scenarios[i]);
      sb.check_result(scenarios[i]);
      drv.cleanup_after_check();
      $display("--------------------------------------------------");
    end
    
    $display("==================================================");
    $display("MBTRAIN CLASS-BASED REGRESSION SUMMARY");
    $display("==================================================");
    $display("TOTAL SCENARIOS : %0d", scenarios.size());
    $display("PASSED          : %0d", sb.pass_count);
    $display("FAILED          : %0d", sb.fail_count);
    $display("OVERALL RESULT : %s", (sb.fail_count == 0) ? "PASS" : "FAIL");
    $display("==================================================");
  endtask
endclass
