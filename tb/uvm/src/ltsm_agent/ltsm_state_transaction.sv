// =============================================================================
//  ltsm_state_transaction
// -----------------------------------------------------------------------------
//  Transaction object capturing a snapshot of the LTSM states.
// =============================================================================

class ltsm_state_transaction extends uvm_sequence_item;
  `uvm_object_utils(ltsm_state_transaction)

  int                                  die_idx; // 0 = Local, 1 = Partner
  ltsm_state_n_pkg::state_n_e          log_state;
  LTSM_state_pkg::LTSM_state_e         ctrl_state;

  function new(string name = "ltsm_state_transaction");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("die=%0d log=%s ctrl=%s", 
                     die_idx, log_state.name(), ctrl_state.name());
  endfunction
endclass
