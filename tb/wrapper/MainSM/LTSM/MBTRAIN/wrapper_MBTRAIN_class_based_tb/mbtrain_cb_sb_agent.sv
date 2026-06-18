`timescale 1ns/1ps

class mbtrain_cb_sb_agent;
    typedef struct {
        logic [7:0]  msg;
        logic [15:0] info;
        logic [63:0] data;
        int          generation;
        int          due_cycle;
    } sb_loopback_item_s;

    virtual mbtrain_cb_if vif;
    mbtrain_cb_config cfg;
    sb_loopback_item_s pending_q[$];
    int cycle_count;
    bit rx_drive_active;

    function new(virtual mbtrain_cb_if vif, mbtrain_cb_config cfg);
        this.vif = vif;
        this.cfg = cfg;
        cycle_count = 0;
        rx_drive_active = 1'b0;
    endfunction

    task run();
        forever begin
            @(negedge vif.lclk);
            cycle_count++;

            if (!vif.rst_n) begin
                pending_q.delete();
                rx_drive_active = 1'b0;
                vif.clear_rx_msg();
            end else begin
                if (rx_drive_active) begin
                    vif.clear_rx_msg();
                    rx_drive_active = 1'b0;
                end

                if (vif.mbtrain_en && vif.substate_tx_sb_msg_valid) begin
                    enqueue_loopback();
                end

                if (!rx_drive_active && pending_q.size() != 0) begin
                    sb_loopback_item_s item;
                    item = pending_q[0];

                    if (item.generation != cfg.scenario_generation) begin
                        void'(pending_q.pop_front());
                    end else if (item.due_cycle <= cycle_count) begin
                        void'(pending_q.pop_front());
                        vif.rx_sb_msg_valid = 1'b1;
                        vif.rx_sb_msg       = item.msg;
                        vif.rx_msginfo      = item.info;
                        vif.rx_data_field   = item.data;
                        rx_drive_active = 1'b1;
                    end
                end
            end
        end
    endtask

    function void enqueue_loopback();
        sb_loopback_item_s item;
        msg_no_e msg_name;

        item.msg        = vif.substate_tx_sb_msg;
        item.info       = vif.substate_tx_msginfo;
        item.data       = vif.substate_tx_data_field;
        item.generation = cfg.scenario_generation;
        item.due_cycle  = cycle_count + cfg.sb_delay_cycles;
        msg_name        = msg_no_e'(item.msg);

        if (cfg.suppress_response_en && item.msg == cfg.suppress_response_msg) begin
            $display("[INJECT] Suppressing SB loopback for msg=%s", msg_name.name());
            return;
        end

        pending_q.push_back(item);
    endfunction

endclass
