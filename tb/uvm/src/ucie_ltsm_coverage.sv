// =============================================================================
//  ucie_ltsm_coverage
// -----------------------------------------------------------------------------
//  UVM Coverage Collector class for the LTSM.
//  Uses the uvm_analysis_imp_decl macro to declare unique analysis imports
//  for Die 0 (Local) and Die 1 (Partner) transactions.
// =============================================================================

`uvm_analysis_imp_decl(_die0_ltsm)
`uvm_analysis_imp_decl(_die1_ltsm)

class ucie_ltsm_coverage extends uvm_component;
  `uvm_component_utils(ucie_ltsm_coverage)

  // Unique analysis exports
  uvm_analysis_imp_die0_ltsm#(ltsm_state_transaction, ucie_ltsm_coverage) die0_export;
  uvm_analysis_imp_die1_ltsm#(ltsm_state_transaction, ucie_ltsm_coverage) die1_export;

  // --- Tracked Previous Values to Filter Samples ---
  ltsm_state_n_pkg::state_n_e    prev_log0,  prev_log1;
  LTSM_state_pkg::LTSM_state_e   prev_ctrl0, prev_ctrl1;

  // =========================================================================
  // COVERGROUPS
  // =========================================================================

  // A. Detailed Chapter 9 Status Log states & transitions (sampled on log_state changes)
  covergroup cg_log_state_die0 with function sample(ltsm_state_n_pkg::state_n_e log_state);
    cp_log_state: coverpoint log_state {
      bins log_states[] = {
        ltsm_state_n_pkg::LOG_RESET,                  ltsm_state_n_pkg::LOG_SBINIT,
        ltsm_state_n_pkg::LOG_MBINIT_PARAM,           ltsm_state_n_pkg::LOG_MBINIT_CAL,
        ltsm_state_n_pkg::LOG_MBINIT_REPAIRCLK,        ltsm_state_n_pkg::LOG_MBINIT_REPAIRVAL,
        ltsm_state_n_pkg::LOG_MBINIT_REVERSALMB,       ltsm_state_n_pkg::LOG_MBINIT_REPAIRMB,
        ltsm_state_n_pkg::LOG_MBTRAIN_VALVREF,         ltsm_state_n_pkg::LOG_MBTRAIN_DATAVREF,
        ltsm_state_n_pkg::LOG_MBTRAIN_SPEEDIDLE,       ltsm_state_n_pkg::LOG_MBTRAIN_TXSELFCAL,
        ltsm_state_n_pkg::LOG_MBTRAIN_RXCLKCAL,        ltsm_state_n_pkg::LOG_MBTRAIN_VALTRAINCENTER,
        ltsm_state_n_pkg::LOG_MBTRAIN_VALTRAINVREF,     ltsm_state_n_pkg::LOG_MBTRAIN_DATATRAINCENTER1,
        ltsm_state_n_pkg::LOG_MBTRAIN_DATATRAINVREF,    ltsm_state_n_pkg::LOG_MBTRAIN_RXDESKEW,
        ltsm_state_n_pkg::LOG_MBTRAIN_DATATRAINCENTER2, ltsm_state_n_pkg::LOG_MBTRAIN_LINKSPEED,
        ltsm_state_n_pkg::LOG_MBTRAIN_REPAIR,          ltsm_state_n_pkg::LOG_PHYRETRAIN,
        ltsm_state_n_pkg::LOG_LINKINIT,               ltsm_state_n_pkg::LOG_ACTIVE,
        ltsm_state_n_pkg::LOG_TRAINERROR,             ltsm_state_n_pkg::LOG_L1_L2,
        ltsm_state_n_pkg::LOG_L1,                      ltsm_state_n_pkg::LOG_L2
      };
    }
    
    cp_loops: coverpoint log_state {
      // Normal Happy Path
      bins path_normal_train   = (ltsm_state_n_pkg::LOG_RESET => ltsm_state_n_pkg::LOG_SBINIT 
                                  => ltsm_state_n_pkg::LOG_MBINIT_PARAM => ltsm_state_n_pkg::LOG_MBINIT_CAL 
                                  => ltsm_state_n_pkg::LOG_MBTRAIN_VALVREF => ltsm_state_n_pkg::LOG_LINKINIT 
                                  => ltsm_state_n_pkg::LOG_ACTIVE);
      
      // Successful Lane Repair (Loops back to TXSELFCAL)
      bins path_repair_degrade = (ltsm_state_n_pkg::LOG_MBTRAIN_TXSELFCAL => ltsm_state_n_pkg::LOG_MBTRAIN_REPAIR 
                                  => ltsm_state_n_pkg::LOG_MBTRAIN_TXSELFCAL => ltsm_state_n_pkg::LOG_ACTIVE);
                                  
      // Repair Failure (Falls back to SpeedIdle)
      bins path_repair_fail    = (ltsm_state_n_pkg::LOG_MBTRAIN_REPAIR => ltsm_state_n_pkg::LOG_MBTRAIN_SPEEDIDLE 
                                  => ltsm_state_n_pkg::LOG_MBTRAIN_TXSELFCAL);
                                  
      // Speed Degradation Loop
      bins path_speed_degrade  = (ltsm_state_n_pkg::LOG_MBTRAIN_RXCLKCAL => ltsm_state_n_pkg::LOG_MBTRAIN_SPEEDIDLE 
                                  => ltsm_state_n_pkg::LOG_MBTRAIN_TXSELFCAL => ltsm_state_n_pkg::LOG_ACTIVE);

      // Falls back all the way to TRAINERROR
      bins path_to_trainerror  = (ltsm_state_n_pkg::LOG_MBTRAIN_SPEEDIDLE => ltsm_state_n_pkg::LOG_MBTRAIN_TXSELFCAL 
                                  => ltsm_state_n_pkg::LOG_TRAINERROR);

      // Recovery path after TrainError
      bins path_recovery       = (ltsm_state_n_pkg::LOG_TRAINERROR => ltsm_state_n_pkg::LOG_RESET 
                                  => ltsm_state_n_pkg::LOG_SBINIT => ltsm_state_n_pkg::LOG_ACTIVE);
    }
  endgroup

  // B. Main LTSM Controller states (sampled on ctrl_state changes)
  covergroup cg_ctrl_state_die0 with function sample(LTSM_state_pkg::LTSM_state_e ctrl_state);
    cp_ctrl: coverpoint ctrl_state {
      bins ctrl_states[] = {
        LTSM_state_pkg::RESET,      LTSM_state_pkg::SBINIT,
        LTSM_state_pkg::MBINIT,     LTSM_state_pkg::MBTRAIN,
        LTSM_state_pkg::LINKINIT,   LTSM_state_pkg::ACTIVE,
        LTSM_state_pkg::PHYRETRAIN, LTSM_state_pkg::L1,
        LTSM_state_pkg::L2,         LTSM_state_pkg::TRAINERROR
      };
    }
  endgroup

  // (Declare identical set of covergroups for Die 1)
  covergroup cg_log_state_die1 with function sample(ltsm_state_n_pkg::state_n_e log_state);
    cp_log_state: coverpoint log_state;
    cp_loops: coverpoint log_state {
      bins path_normal_train   = (ltsm_state_n_pkg::LOG_RESET => ltsm_state_n_pkg::LOG_SBINIT 
                                  => ltsm_state_n_pkg::LOG_MBINIT_PARAM => ltsm_state_n_pkg::LOG_MBINIT_CAL 
                                  => ltsm_state_n_pkg::LOG_MBTRAIN_VALVREF => ltsm_state_n_pkg::LOG_LINKINIT 
                                  => ltsm_state_n_pkg::LOG_ACTIVE);
      bins path_repair_degrade = (ltsm_state_n_pkg::LOG_MBTRAIN_TXSELFCAL => ltsm_state_n_pkg::LOG_MBTRAIN_REPAIR 
                                  => ltsm_state_n_pkg::LOG_MBTRAIN_TXSELFCAL => ltsm_state_n_pkg::LOG_ACTIVE);
    }
  endgroup

  covergroup cg_ctrl_state_die1 with function sample(LTSM_state_pkg::LTSM_state_e ctrl_state);
    cp_ctrl: coverpoint ctrl_state;
  endgroup

  // =========================================================================
  // METHODS
  // =========================================================================

  function new(string name = "ucie_ltsm_coverage", uvm_component parent = null);
    super.new(name, parent);
    
    die0_export = new("die0_export", this);
    die1_export = new("die1_export", this);

    // Instantiate Die 0 groups
    cg_log_state_die0   = new();
    cg_ctrl_state_die0  = new();

    // Instantiate Die 1 groups
    cg_log_state_die1   = new();
    cg_ctrl_state_die1  = new();

    // Initialize tracking variables to reset defaults
    prev_log0  = ltsm_state_n_pkg::LOG_RESET;
    prev_ctrl0 = LTSM_state_pkg::RESET;

    prev_log1  = ltsm_state_n_pkg::LOG_RESET;
    prev_ctrl1 = LTSM_state_pkg::RESET;
  endfunction

  // Write implementation for Die 0 state change transactions
  virtual function void write_die0_ltsm(ltsm_state_transaction t);
    // 1. Log State Coverage
    if (t.log_state != prev_log0) begin
      cg_log_state_die0.sample(t.log_state);
      prev_log0 = t.log_state;
    end

    // 2. Control State Coverage
    if (t.ctrl_state != prev_ctrl0) begin
      cg_ctrl_state_die0.sample(t.ctrl_state);
      prev_ctrl0 = t.ctrl_state;
    end
  endfunction

  // Write implementation for Die 1 state change transactions
  virtual function void write_die1_ltsm(ltsm_state_transaction t);
    // 1. Log State Coverage
    if (t.log_state != prev_log1) begin
      cg_log_state_die1.sample(t.log_state);
      prev_log1 = t.log_state;
    end

    // 2. Control State Coverage
    if (t.ctrl_state != prev_ctrl1) begin
      cg_ctrl_state_die1.sample(t.ctrl_state);
      prev_ctrl1 = t.ctrl_state;
    end
  endfunction

endclass
