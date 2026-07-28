// =============================================================================
//  ucie_reg_predictor
// -----------------------------------------------------------------------------
//  Custom register predictor validating bus operation responses against hardware
//  access rules (unmapped addresses, write to read-only locations) and filtering out
//  error completions from updating the RAL mirror.
// =============================================================================

class ucie_reg_access_status_info;
  const uvm_status_e status;
  const string       info;

  function new(uvm_status_e status, string info);
    this.status = status;
    this.info   = info;
  endfunction

  static function ucie_reg_access_status_info new_instance(uvm_status_e status, string info);
    ucie_reg_access_status_info result = new(status, info);
    return result;
  endfunction
endclass

class ucie_reg_predictor#(type BUSTYPE = rdi_cfg_seq_item_mon) extends uvm_reg_predictor#(BUSTYPE);
  `uvm_component_param_utils(ucie_reg_predictor#(BUSTYPE))

  uvm_event predict_ev;

  function new(string name = "ucie_reg_predictor", uvm_component parent = null);
    super.new(name, parent);
    predict_ev = new("predict_ev");
  endfunction

  // Getter for the expected bus operation response
  protected virtual function ucie_reg_access_status_info get_exp_response(uvm_reg_bus_op operation);
    uvm_reg register;

    register = map.get_reg_by_offset(operation.addr, (operation.kind == UVM_READ));

    // 1. Any access to an unmapped register address must return UVM_NOT_OK
    if (register == null) begin
      return ucie_reg_access_status_info::new_instance(UVM_NOT_OK, "Access to an unmapped register address");
    end

    // 2. Any write access to a full read-only register must return UVM_NOT_OK
    if (operation.kind == UVM_WRITE) begin
      uvm_reg_map_info info = map.get_reg_map_info(register);
      if (info.rights == "RO") begin
        return ucie_reg_access_status_info::new_instance(UVM_NOT_OK, "Write access to a read-only register");
      end
    end

    return ucie_reg_access_status_info::new_instance(UVM_IS_OK, "Access OK");
  endfunction

  virtual function void write(BUSTYPE tr);
    uvm_reg_bus_op operation;

    adapter.bus2reg(tr, operation);

    begin
      ucie_reg_access_status_info exp_response = get_exp_response(operation);

      if (exp_response.status != operation.status) begin
        `uvm_error("DUT_ERROR", $sformatf("Mismatch detected for bus operation status - expected: %0s, received: %0s on access: %0s - reason: %0s",
                                          exp_response.status.name(), operation.status.name(), tr.convert2string(), exp_response.info))
      end
    end

    // Update RAL model mirror only on successful completions
    if (operation.status == UVM_IS_OK) begin
      super.write(tr);
    end

    predict_ev.trigger();
  endfunction

endclass
