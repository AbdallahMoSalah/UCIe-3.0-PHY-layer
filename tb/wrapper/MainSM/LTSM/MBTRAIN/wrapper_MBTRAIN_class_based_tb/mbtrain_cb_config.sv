class mbtrain_cb_config;
    int sb_delay_cycles = 10;
    int watchdog_cycles = 100000;
    int analog_settle_cycles = 20;
    logic[2:0] def_rx_mask = 3'b011;
    logic[2:0] def_tx_mask = 3'b011;
    logic[15:0] def_d2c_pass_mask = 16'hFFFF;
    logic[15:0] current_train_pass_mask = 16'hFFFF;
    logic[15:0] linkspeed_pass_q[$];
    int linkspeed_sweep_index = 0;
    bit suppress_response_en = 1'b0;
    logic [7:0] suppress_response_msg = 8'h00;
    bit last_timeout = 1'b0;
    bit enable_verbose = 0;
    bit stop_on_first_fail = 1;
    int scenario_generation = 0;

    function void begin_scenario();
        scenario_generation++;
        linkspeed_sweep_index = 0;
        last_timeout = 1'b0;
        suppress_response_en = 1'b0;
        suppress_response_msg = 8'h00;
    endfunction

    function void configure_linkspeed_script(logic [15:0] script_q[$], logic [15:0] fallback_mask);
        linkspeed_pass_q.delete();
        foreach (script_q[i]) begin
            linkspeed_pass_q.push_back(script_q[i]);
        end
        if (linkspeed_pass_q.size() == 0) begin
            linkspeed_pass_q.push_back(fallback_mask);
        end
        linkspeed_sweep_index = 0;
    endfunction

    function logic [15:0] next_linkspeed_pass_mask();
        logic [15:0] mask;

        if (linkspeed_pass_q.size() == 0) begin
            mask = def_d2c_pass_mask;
        end else if (linkspeed_sweep_index < linkspeed_pass_q.size()) begin
            mask = linkspeed_pass_q[linkspeed_sweep_index];
        end else begin
            mask = linkspeed_pass_q[linkspeed_pass_q.size()-1];
        end

        linkspeed_sweep_index++;
        return mask;
    endfunction
endclass
