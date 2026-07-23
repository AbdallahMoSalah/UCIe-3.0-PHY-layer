// =============================================================================
//  rdi_cfg_driver
// -----------------------------------------------------------------------------
//  Base driver class for RDI Config Agent. Contains agent configuration reference
//  and virtual interface handle.
// =============================================================================

class rdi_cfg_driver extends uvm_driver #(rdi_cfg_seq_item) implements rdi_cfg_reset_handler;
  `uvm_component_utils(rdi_cfg_driver)

  rdi_cfg_agent_config agent_config;
  virtual rdi_cfg_if   vif;

  protected process process_drive_transactions;

  function new(string name = "rdi_cfg_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(rdi_cfg_agent_config)::get(this, "", "cfg", agent_config));
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (agent_config != null) begin
      vif = agent_config.get_vif();
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever begin
      fork
        begin
          wait_reset_end();
          drive_transactions();
          disable fork;
        end
      join
    end
  endtask

  protected virtual task wait_reset_end();
    if (agent_config != null) begin
      agent_config.wait_reset_end();
    end
  endtask

  // Task which drives one single item on the bus (overridden by master driver)
  protected virtual task drive_transaction(rdi_cfg_seq_item item);
    `uvm_fatal("ALGORITHM_ISSUE", "Implement drive_transaction()")
  endtask

  // Base task for driving transactions (overridden if necessary by slave driver)
  protected virtual task drive_transactions();
    fork
      begin
        process_drive_transactions = process::self();
        forever begin
          rdi_cfg_seq_item item;
          seq_item_port.get_next_item(item);
          drive_transaction(item);
          seq_item_port.item_done();
        end
      end
    join
  endtask

  virtual function void handle_reset(uvm_phase phase);
    if (process_drive_transactions != null) begin
      process_drive_transactions.kill();
      process_drive_transactions = null;
    end
  endfunction

endclass
