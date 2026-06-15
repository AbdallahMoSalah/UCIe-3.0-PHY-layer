// ====================================================================================================
// unit_REPAIR_partner.sv — MBTRAIN.REPAIR PARTNER (Responder) FSM
//
// This is the PARTNER side of the decoupled REPAIR substate (Standard Package width degrade).
//
// ROLE (PARTNER = DECISION-MAKER for final TX/RX lane masks):
//   - Waits for the remote Local FSM's {apply degrade req} which carries their TX code.
//   - Knows our own best TX code (degraded_tx_lane_map_code, from unit_negotiated_lanes).
//   - Applies the UCIe spec Step 2 decision rules to set our final mb_tx and mb_rx lane masks.
//   - Sends {apply degrade resp} with NO data (pure acknowledgment).
//   - Exits to TRAINERROR if either side encoded "Degrade not possible" (3'b000).
//
// ====================================================================================================
// DECISION TABLE (applied at SEND_DEGRADE, for both X16 and X8 module types):
//
//  Let FULL = "all functional" code for this module:
//    X16 module (rf_ctrl_target_link_width == 4'h2, SPMW=0, UCIe-S-x8=0): FULL = 3'b011
//    X8  module (rf_ctrl_target_link_width == 4'h1 OR SPMW=1 OR UCIe-S-x8=1): FULL = 3'b001
//
//  +-------------------------------+------------------------------+----------+----------+
//  | remote_local_tx_code_r        | degraded_tx_lane_map_code    | TX mask  | RX mask  |
//  +-------------------------------+------------------------------+----------+----------+
//  | 3'b000 (degrade not possible) | any                          | → TRAINERROR        |
//  | any                           | 3'b000 (not feasible)        | → TRAINERROR        |
//  | FULL  (all lanes functional)  | any valid degrade            | our code | our code |
//  | specific degrade              | FULL (all our lanes ok)      | remote   | remote   |
//  | specific degrade              | specific degrade             | our code | remote   |
//  +-------------------------------+------------------------------+----------+----------+
//
//  Example (X16 module, FULL = 3'b011):
//    remote=3'b011, ours=3'b010 → TX=3'b010, RX=3'b010  (remote all-ok, use ours)
//    remote=3'b010, ours=3'b011 → TX=3'b010, RX=3'b010  (we're all-ok, adopt remote)
//    remote=3'b010, ours=3'b001 → TX=3'b001, RX=3'b010  (both degrade, TX=ours, RX=remote)
//
//  Example (X8 module, FULL = 3'b001):
//    remote=3'b001, ours=3'b100 → TX=3'b100, RX=3'b100  (remote all-ok, use ours)
//    remote=3'b100, ours=3'b001 → TX=3'b100, RX=3'b100  (we're all-ok, adopt remote)
//    remote=3'b100, ours=3'b101 → TX=3'b101, RX=3'b100  (both degrade, TX=ours, RX=remote)
//
// ====================================================================================================
// Sideband Messages Used in MBTRAIN.REPAIR (Partner — Responder):
// +-------------------------------------------+-----------+------------------------------------------+
// | Message Name                              | Direction | MsgInfo & Data Field Details             |
// +-------------------------------------------+-----------+------------------------------------------+
// | {MBTRAIN.REPAIR init req}                 | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0              |
// | {MBTRAIN.REPAIR init resp}                | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0              |
// | {MBTRAIN.REPAIR apply degrade req}        | In  (RX)  | MsgInfo[2:0]: remote Local TX code       |
// | {MBTRAIN.REPAIR apply degrade resp}       | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0 (NO data)   |
// | {MBTRAIN.REPAIR end req}                  | In  (RX)  | MsgInfo: 16'h0, Data: 64'h0              |
// | {MBTRAIN.REPAIR end resp}                 | Out (TX)  | MsgInfo: 16'h0, Data: 64'h0              |
// +-------------------------------------------+-----------+------------------------------------------+
// ====================================================================================================

module unit_REPAIR_partner (
        // Clock and Reset Signals
        input  logic        lclk,
        input  logic        rst_n,

        // LTSM Control Signals
        input  logic        repair_en,
        input  logic        soft_rst_n,
        output logic        repair_done,
        output logic        txselfcal_req,
        output logic        trainerror_req,

        // Width Degradation Inputs (our TX side, computed by unit_negotiated_lanes in the wrapper)
        input  logic [2:0]  degraded_tx_lane_map_code, // Our best TX degraded lane code
        input  logic        width_degrade_feasible,     // 1 = our TX code is valid (!= 3'b000)

        // Module type: determines what "all functional" means for this link.
        //   1 = X16 standard package (FULL code = 3'b011)
        //   0 = X8  standard package or X8 forced mode (FULL code = 3'b001)
        input  logic        is_x16_module,

        // Lane mask outputs — PARTNER is the sole owner of both TX and RX masks for our die.
        output logic [2:0]  mb_rx_data_lane_mask,
        input  logic [2:0]  mbinit_rx_data_lane_mask,   // Initial mask from LTSM controller
        output logic [2:0]  mb_tx_data_lane_mask,
        input  logic [2:0]  mbinit_tx_data_lane_mask,   // Initial mask from LTSM controller
        input  logic        update_lane_mask,            // 1 = load mbinit values (override)

        // MB TX/RX Lane Control
        output logic [1:0]  mb_tx_clk_lane_sel,
        output logic [1:0]  mb_tx_data_lane_sel,
        output logic [1:0]  mb_tx_val_lane_sel,
        output logic [1:0]  mb_tx_trk_lane_sel,
        output logic        mb_rx_clk_lane_sel,
        output logic        mb_rx_data_lane_sel,
        output logic        mb_rx_val_lane_sel,
        output logic        mb_rx_trk_lane_sel,

        // Sideband Control Signals
        output logic        tx_sb_msg_valid,
        output logic [7:0]  tx_sb_msg,
        output logic [15:0] tx_msginfo,
        output logic [63:0] tx_data_field,

        input  logic        rx_sb_msg_valid,
        input  logic [7:0]  rx_sb_msg,
        input  logic [15:0] rx_msginfo,
        input  logic [63:0] rx_data_field
    );

    import UCIe_pkg::*;

    // =========================================================================
    // Lane map encoding constants (from unit_negotiated_lanes)
    // =========================================================================
    // X16 module: 3'b011 = all 16 lanes active (= "all functional" for X16)
    // X8  module: 3'b001 = all  8 lanes active (= "all functional" for X8)
    localparam [2:0] CODE_X16_FULL = 3'b011; // X16 all-functional code
    localparam [2:0] CODE_X8_FULL  = 3'b001; // X8  all-functional code (also X8-low-half in X16)
    localparam [2:0] CODE_NONE     = 3'b000; // Degrade not possible

    // =========================================================================
    // State encoding
    // =========================================================================
    typedef enum logic [3:0] {
        REPAIR_PTR_IDLE          = 4'd0,
        REPAIR_PTR_WAIT_INIT     = 4'd1,
        REPAIR_PTR_SEND_INIT     = 4'd2,
        REPAIR_PTR_WAIT_DEGRADE  = 4'd3,
        REPAIR_PTR_SEND_DEGRADE  = 4'd4,
        REPAIR_PTR_WAIT_END      = 4'd5,
        REPAIR_PTR_SEND_END      = 4'd6,
        REPAIR_PTR_DONE          = 4'd7,
        REPAIR_PTR_TO_TRAINERROR = 4'd8
    } linkspeed_ptr_state_e;

    linkspeed_ptr_state_e current_state, next_state;

    // =========================================================================
    // Registers
    // =========================================================================
    reg [2:0] mb_rx_data_lane_mask_r; // Our final RX lane mask (set by decision logic)
    reg [2:0] mb_tx_data_lane_mask_r; // Our final TX lane mask (set by decision logic)

    // Captured remote Local's TX lane map code from the apply-degrade req.
    reg [2:0] remote_local_tx_code_r;

    assign mb_rx_data_lane_mask = mb_rx_data_lane_mask_r;
    assign mb_tx_data_lane_mask = mb_tx_data_lane_mask_r;

    // =========================================================================
    // "All functional" code — depends on module type
    // =========================================================================
    // X16 module: full width = 3'b011 (all 16 lanes active)
    // X8  module: full width = 3'b001 (all  8 lanes active, which IS full width for X8)
    wire [2:0] full_width_code;
    assign full_width_code = is_x16_module ? CODE_X16_FULL : CODE_X8_FULL;

    // =========================================================================
    // FSM State Register
    // =========================================================================
    always_ff @(posedge lclk or negedge rst_n) begin : STATE_REG
        if (!rst_n) begin
            current_state          <= REPAIR_PTR_IDLE;
            mb_rx_data_lane_mask_r <= 3'b000;
            mb_tx_data_lane_mask_r <= 3'b000;
            remote_local_tx_code_r <= 3'b000;
        end else if (!soft_rst_n) begin
            current_state          <= REPAIR_PTR_IDLE;
            mb_rx_data_lane_mask_r <= 3'b000;
            mb_tx_data_lane_mask_r <= 3'b000;
            remote_local_tx_code_r <= 3'b000;
        end else begin
            current_state <= next_state;

            // ------------------------------------------------------------------
            // LTSM controller override: reload initial masks (highest priority).
            // ------------------------------------------------------------------
            if (update_lane_mask) begin
                mb_rx_data_lane_mask_r <= mbinit_rx_data_lane_mask;
                mb_tx_data_lane_mask_r <= mbinit_tx_data_lane_mask;
            end

            // ------------------------------------------------------------------
            // Capture the remote Local's TX code from the {apply degrade req}.
            // This is the code Die B's LOCAL encoded in MsgInfo[2:0]:
            //   3'b000 = degrade not possible on Die B
            //   other  = Die B's TX will use these lanes
            // ------------------------------------------------------------------
            if (current_state == REPAIR_PTR_WAIT_DEGRADE
                    && rx_sb_msg_valid && rx_sb_msg == MBTRAIN_REPAIR_apply_degrade_req) begin
                remote_local_tx_code_r <= rx_msginfo[2:0];
            end

            // ------------------------------------------------------------------
            // Apply the final TX/RX lane masks when SEND_DEGRADE is entered
            // (i.e. when both TX codes are known: ours from unit_negotiated_lanes,
            // Die B's from the captured remote_local_tx_code_r).
            //
            // UCIe Spec Step 2 decision rules (generalized for X16 and X8):
            //
            //   TRAINERROR cases (handled in NEXT_STATE — no mask update):
            //     remote_local_tx_code_r == 3'b000   (Die B: degrade not possible)
            //     !width_degrade_feasible             (we:    degrade not possible)
            //
            //   Case A — Remote indicated ALL FUNCTIONAL (remote == full_width_code):
            //     → TX = our code,   RX = our code
            //
            //   Case B — WE indicated ALL FUNCTIONAL (ours == full_width_code):
            //     → TX = remote code, RX = remote code
            //
            //   Case C — BOTH have specific degrades (neither is full_width_code):
            //     → TX = our code,   RX = remote code
            // ------------------------------------------------------------------
            if (current_state == REPAIR_PTR_SEND_DEGRADE && width_degrade_feasible
                    && remote_local_tx_code_r != CODE_NONE) begin
                if (remote_local_tx_code_r == full_width_code) begin
                    // Case A: Die B said all lanes functional → use our own code
                    mb_tx_data_lane_mask_r <= degraded_tx_lane_map_code;
                    mb_rx_data_lane_mask_r <= degraded_tx_lane_map_code;
                end else if (degraded_tx_lane_map_code == full_width_code) begin
                    // Case B: We said all functional but Die B has a degrade → adopt Die B's code
                    mb_tx_data_lane_mask_r <= remote_local_tx_code_r;
                    mb_rx_data_lane_mask_r <= remote_local_tx_code_r;
                end else begin
                    // Case C: Both sides have specific degrades (independent paths allowed)
                    mb_tx_data_lane_mask_r <= degraded_tx_lane_map_code; // our TX degrade
                    mb_rx_data_lane_mask_r <= remote_local_tx_code_r;    // Die B's TX = our RX
                end
            end
        end
    end

    // =========================================================================
    // Next State Logic
    // =========================================================================
    always_comb begin : NEXT_STATE_LOGIC
        next_state = current_state;

        // TRAINERROR global overrides
        if (rx_sb_msg_valid && rx_sb_msg == TRAINERROR_Entry_req) begin
            next_state = REPAIR_PTR_TO_TRAINERROR;
        end else if (!repair_en) begin
            next_state = REPAIR_PTR_IDLE;
        end else begin
            case (current_state)
                REPAIR_PTR_IDLE: begin
                    if (repair_en) begin
                        next_state = REPAIR_PTR_WAIT_INIT;
                    end
                end

                REPAIR_PTR_WAIT_INIT: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_REPAIR_init_req) begin
                        next_state = REPAIR_PTR_SEND_INIT;
                    end
                end

                REPAIR_PTR_SEND_INIT: begin
                    next_state = REPAIR_PTR_WAIT_DEGRADE;
                end

                REPAIR_PTR_WAIT_DEGRADE: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_REPAIR_apply_degrade_req) begin
                        next_state = REPAIR_PTR_SEND_DEGRADE;
                    end
                end

                REPAIR_PTR_SEND_DEGRADE: begin
                    // TRAINERROR if either side encoded "Degrade not possible" (3'b000).
                    if (!width_degrade_feasible || (remote_local_tx_code_r == CODE_NONE)) begin
                        next_state = REPAIR_PTR_TO_TRAINERROR;
                    end else begin
                        next_state = REPAIR_PTR_WAIT_END;
                    end
                end

                REPAIR_PTR_WAIT_END: begin
                    if (rx_sb_msg_valid && rx_sb_msg == MBTRAIN_REPAIR_end_req) begin
                        next_state = REPAIR_PTR_SEND_END;
                    end
                end

                REPAIR_PTR_SEND_END: begin
                    next_state = REPAIR_PTR_DONE;
                end

                REPAIR_PTR_DONE: begin
                    if (!repair_en) begin
                        next_state = REPAIR_PTR_IDLE;
                    end
                end

                REPAIR_PTR_TO_TRAINERROR: begin
                    if (!repair_en) begin
                        next_state = REPAIR_PTR_IDLE;
                    end
                end

                default: next_state = REPAIR_PTR_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Output Logic
    // =========================================================================
    always_comb begin : OUTPUT_LOGIC
        // Defaults
        repair_done         = 1'b0;
        txselfcal_req       = 1'b0;
        trainerror_req      = 1'b0;

        // Mainband Defaults during REPAIR (spec §4.5.3.4.13):
        //   Track, Data, Valid TX held low (2'b00).
        //   Clock TX held differential/simultaneous low (2'b01).
        //   Clock RX enabled (1'b1), other RX disabled (1'b0).
        mb_tx_clk_lane_sel  = 2'b01;
        mb_tx_data_lane_sel = 2'b00;
        mb_tx_val_lane_sel  = 2'b00;
        mb_tx_trk_lane_sel  = 2'b00;
        mb_rx_clk_lane_sel  = 1'b1;
        mb_rx_data_lane_sel = 1'b0;
        mb_rx_val_lane_sel  = 1'b0;
        mb_rx_trk_lane_sel  = 1'b0;

        tx_sb_msg_valid     = 1'b0;
        tx_sb_msg           = NOTHING;
        tx_msginfo          = 16'h0;
        tx_data_field       = 64'h0;

        case (current_state)
            REPAIR_PTR_IDLE: begin
                mb_tx_clk_lane_sel  = 2'b00;
                mb_tx_data_lane_sel = 2'b00;
                mb_tx_val_lane_sel  = 2'b00;
                mb_tx_trk_lane_sel  = 2'b00;
                mb_rx_clk_lane_sel  = 1'b0;
                mb_rx_data_lane_sel = 1'b0;
                mb_rx_val_lane_sel  = 1'b0;
                mb_rx_trk_lane_sel  = 1'b0;
            end

            REPAIR_PTR_WAIT_INIT: begin
                // Waiting for {MBTRAIN.REPAIR init req}
            end

            REPAIR_PTR_SEND_INIT: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_REPAIR_init_resp;
            end

            REPAIR_PTR_WAIT_DEGRADE: begin
                // Waiting for {MBTRAIN.REPAIR apply degrade req}
            end

            REPAIR_PTR_SEND_DEGRADE: begin
                // Send pure acknowledgment — NO data, NO lane code in msginfo.
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_REPAIR_apply_degrade_resp;
                // tx_msginfo = 16'h0 (default) — resp carries no data per spec.
            end

            REPAIR_PTR_WAIT_END: begin
                // Waiting for {MBTRAIN.REPAIR end req}
            end

            REPAIR_PTR_SEND_END: begin
                tx_sb_msg_valid = 1'b1;
                tx_sb_msg       = MBTRAIN_REPAIR_end_resp;
            end

            REPAIR_PTR_DONE: begin
                repair_done      = 1'b1;
                txselfcal_req    = 1'b1;
            end

            REPAIR_PTR_TO_TRAINERROR: begin
                repair_done      = 1'b1;
                trainerror_req   = 1'b1;
            end

            default: begin
                // Safe defaults already assigned above
            end
        endcase
    end

endmodule
