`timescale 1ns/1ps

class mbtrain_cb_d2c_model;
    virtual mbtrain_cb_if vif;
    mbtrain_cb_config cfg;

    function new(virtual mbtrain_cb_if vif, mbtrain_cb_config cfg);
        this.vif = vif;
        this.cfg = cfg;
    endfunction

    task run();
        int analog_count;
        int observed_generation;

        // Initialize default values
        vif.sweep_done <= 0;
        vif.sweep_swept_code <= 0;
        for (int i=0; i<16; i++) vif.sweep_best_code[i] <= 0;
        vif.sweep_min_eye_width <= 0;
        vif.analog_settle_time_done <= 0;
        analog_count = 0;
        observed_generation = cfg.scenario_generation;
        
        fork
            // Analog settle timer model
            forever begin
                @(posedge vif.lclk);
                if (!vif.rst_n || (observed_generation != cfg.scenario_generation)) begin
                    observed_generation = cfg.scenario_generation;
                    analog_count = 0;
                    vif.analog_settle_time_done <= 0;
                end else if (vif.analog_settle_timer_en) begin
                    if (analog_count < cfg.analog_settle_cycles) begin
                        analog_count++;
                        vif.analog_settle_time_done <= 0;
                    end else begin
                        vif.analog_settle_time_done <= 1;
                    end
                end else begin
                    analog_count = 0;
                    vif.analog_settle_time_done <= 0;
                end
            end
            
            // Sweep model
            forever begin
                @(posedge vif.lclk);
                if (!vif.rst_n) begin
                    vif.sweep_done <= 0;
                    vif.d2c_perlane_pass <= 16'h0000;
                    vif.sweep_swept_code <= 0;
                    for (int i=0; i<16; i++) vif.sweep_best_code[i] <= 0;
                    vif.sweep_min_eye_width <= 0;
                end else if ((vif.local_sweep_en || vif.partner_sweep_en) && !vif.sweep_done) begin
                    process_sweep();
                end
            end
        join_none
    endtask

    task automatic process_sweep();
        logic [15:0] pass_mask;
        int saved_generation;

        saved_generation = cfg.scenario_generation;
        if (vif.current_mbtrain_substate == LOG_MBTRAIN_LINKSPEED) begin
            pass_mask = cfg.next_linkspeed_pass_mask();
        end else begin
            pass_mask = cfg.current_train_pass_mask;
        end

        // Simulate sweep process
        repeat(8) begin
            @(posedge vif.lclk);
            if (!vif.rst_n || (saved_generation != cfg.scenario_generation)) begin
                return;
            end
        end
        
        vif.d2c_perlane_pass <= pass_mask;
        vif.sweep_done <= 1;
        vif.sweep_swept_code <= 5'd8;
        for (int i=0; i<16; i++) begin
            vif.sweep_best_code[i] <= 5'd8;
        end
        vif.sweep_min_eye_width <= (pass_mask == 16'h0000) ? 5'd0 : 5'd8;

        @(posedge vif.lclk);
        while ((vif.local_sweep_en || vif.partner_sweep_en) && vif.rst_n && (saved_generation == cfg.scenario_generation)) begin
            @(posedge vif.lclk);
        end
        if (saved_generation == cfg.scenario_generation) begin
            vif.sweep_done <= 0;
        end
    endtask

endclass
