// =============================================================================
// mbtrain_cb_coverage.sv — Functional Coverage Collector
// =============================================================================
class mbtrain_cb_coverage;
    import ltsm_state_n_pkg::*;
    import mbtrain_cb_types_pkg::*;

    virtual mbtrain_cb_if vif;
    mbtrain_cb_config     cfg;

    // ── Per-scenario outcome tracking ─────────────────────────────────────────
    mbtrain_width_e           cov_width;
    mbtrain_speed_e           cov_speed;
    mbtrain_expected_exit_e   cov_exit;
    int                       cov_repair_visits;
    int                       cov_speedidle_visits;
    int                       cov_linkspeed_visits;
    logic [2:0]               cov_rx_mask;
    logic [2:0]               cov_tx_mask;

    // ── Coverage bins (tracked in simulation) ─────────────────────────────────
    // Width coverage
    int cvg_width_x16  = 0;
    int cvg_width_x8   = 0;
    int cvg_width_x4   = 0;

    // Speed coverage (bit-vector: bit[i] = speed encoding i was seen)
    bit [7:0] cvg_speed_seen = 8'h00;

    // Exit coverage
    int cvg_exit_linkinit    = 0;
    int cvg_exit_speedidle   = 0;
    int cvg_exit_repair      = 0;
    int cvg_exit_phyretrain  = 0;
    int cvg_exit_trainerror  = 0;
    int cvg_exit_timeout     = 0;
    int cvg_exit_idle        = 0;

    // REPAIR result coverage
    int cvg_repair_x16_x8_low  = 0;
    int cvg_repair_x16_x8_high = 0;
    int cvg_repair_x8_x4_low   = 0;
    int cvg_repair_x8_x4_high  = 0;
    int cvg_repair_not_possible = 0;

    // LINKSPEED visit count coverage (how many times LINKSPEED was visited)
    bit [3:0] cvg_linkspeed_visits_seen = 4'h0; // bits 0-3 for visit counts 1-4

    // RXDESKEW arc count coverage (0-4 arcs seen)
    bit [4:0] cvg_rxdeskew_arcs_seen = 5'h00;

    function new(virtual mbtrain_cb_if v, mbtrain_cb_config c);
        vif = v;
        cfg = c;
    endfunction

    // ── Sample coverage after each scenario ───────────────────────────────────
    task automatic sample_scenario(
        mbtrain_scenario_s     scen,
        mbtrain_cb_monitor     mon,
        bit                    passed
    );
        // Width
        case (scen.width)
            WIDTH_X16: cvg_width_x16++;
            WIDTH_X8:  cvg_width_x8++;
            WIDTH_X4:  cvg_width_x4++;
        endcase

        // Speed (encode index from enum value)
        cvg_speed_seen[int'(scen.speed)] = 1;

        // Exit
        case (scen.expected_exit)
            EXIT_LINKINIT:     cvg_exit_linkinit++;
            EXIT_SPEEDIDLE_LOOP: cvg_exit_speedidle++;
            EXIT_REPAIR_LOOP:  cvg_exit_repair++;
            EXIT_PHYRETRAIN:   cvg_exit_phyretrain++;
            EXIT_TRAINERROR:   cvg_exit_trainerror++;
            EXIT_TIMEOUT:      cvg_exit_timeout++;
            EXIT_IDLE:         cvg_exit_idle++;
        endcase

        // REPAIR result (from final lane masks)
        if (mon.repair_visit_count > 0) begin
            case ({mon.final_rx_lane_mask, mon.final_tx_mask})
                {3'b001, 3'b001}: cvg_repair_x16_x8_low++;
                {3'b010, 3'b010}: cvg_repair_x16_x8_high++;
                {3'b100, 3'b100}: cvg_repair_x8_x4_low++;
                {3'b101, 3'b101}: cvg_repair_x8_x4_high++;
                default:          ;
            endcase
            if (scen.expected_exit == EXIT_TRAINERROR &&
                mon.repair_visit_count >= 1)
                cvg_repair_not_possible++;
        end

        // LINKSPEED visit count (cap at 4 for coverage)
        begin
            int lv = mon.linkspeed_visit_count;
            if (lv >= 1 && lv <= 4)
                cvg_linkspeed_visits_seen[lv-1] = 1;
        end
    endtask

    // ── Print coverage report ─────────────────────────────────────────────────
    function automatic void print_report();
        int speeds_seen = 0;
        $display("");
        $display("==================================================");
        $display("MBTRAIN FUNCTIONAL COVERAGE REPORT");
        $display("==================================================");

        $display("Width Coverage:");
        $display("  x16 : %0d scenario(s)", cvg_width_x16);
        $display("  x8  : %0d scenario(s)", cvg_width_x8);
        $display("  x4  : %0d scenario(s)", cvg_width_x4);

        $display("Speed Coverage (8 encodings):");
        for (int i = 0; i < 8; i++) begin
            if (cvg_speed_seen[i]) begin
                $display("  speed[%0d] = COVERED", i);
                speeds_seen++;
            end else begin
                $display("  speed[%0d] = NOT COVERED", i);
            end
        end
        $display("  Total speeds covered: %0d/8", speeds_seen);

        $display("Exit Coverage:");
        $display("  LINKINIT    : %0d", cvg_exit_linkinit);
        $display("  SPEEDIDLE   : %0d", cvg_exit_speedidle);
        $display("  REPAIR      : %0d", cvg_exit_repair);
        $display("  PHYRETRAIN  : %0d", cvg_exit_phyretrain);
        $display("  TRAINERROR  : %0d", cvg_exit_trainerror);
        $display("  TIMEOUT     : %0d", cvg_exit_timeout);
        $display("  IDLE        : %0d", cvg_exit_idle);

        $display("REPAIR Result Coverage:");
        $display("  x16→x8 low  : %0d", cvg_repair_x16_x8_low);
        $display("  x16→x8 high : %0d", cvg_repair_x16_x8_high);
        $display("  x8→x4 low   : %0d", cvg_repair_x8_x4_low);
        $display("  x8→x4 high  : %0d", cvg_repair_x8_x4_high);
        $display("  not possible: %0d", cvg_repair_not_possible);

        $display("LINKSPEED Visit Count Coverage:");
        for (int i = 0; i < 4; i++) begin
            $display("  %0d visit(s): %s", i+1,
                     cvg_linkspeed_visits_seen[i] ? "COVERED" : "NOT COVERED");
        end

        $display("==================================================");
    endfunction

endclass
