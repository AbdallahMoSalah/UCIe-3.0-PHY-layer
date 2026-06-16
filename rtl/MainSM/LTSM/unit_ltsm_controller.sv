import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import LTSM_state_pkg::*;

// =============================================================================
// LTSM_CONTROLLER
// =============================================================================
// Top-level controller for Link Training State Machine (LTSM).
// Sequentially coordinates transitions across all 10 major LTSM states, 
// multiplexes the shared Sideband TX bus, multiplexes the Mainband outputs, 
// multiplexes and shares the D2C Point Test interface, latches capability
// status registers when MBINIT goes idle, and shifts state logging history.
// =============================================================================

module ltsm_controller
import UCIe_pkg::*;
import ltsm_state_n_pkg::*;
import RDI_SM_pkg :: *;
(
    input  logic clk,
    input  logic rst_n,

    // =========================================================================
    // FSM Control Inputs / Outputs
    // =========================================================================
    input  ltsm_ctrl_state_e active_next_ltsm_state,
    input  logic            active_error,

    output LTSM_state_e     current_ltsm_state,
    output state_n_e        current_ltsm_state_n,
    output logic            link_training_retraining,
    output logic            link_status,

    // Submodule enables / handshakes
    output logic            reset_en,
    input  logic            reset_done,

    output logic            sbinit_en,
    input  logic            sbinit_done,

    output logic            mbinit_en,
    input  logic            mbinit_done,
    input  logic            mbinit_error,

    output logic            mbtrain_en,
    input  logic            mbtrain_done,
    input  logic            mbtrain_error,

    output logic            linkinit_en,
    input  logic            linkinit_done,

    output logic            active_en,

    output logic            phyretrain_en,
    input  logic            phyretrain_done,
    input  logic            phyretrain_error,

    output logic            l1_en,
    input  logic            l1_done,

    output logic            l2_en,
    input  logic            l2_done,

    output logic            trainerror_en,
    input  logic            trainerror_done,

    // =========================================================================
    // Watchdog Timer Interface
    // =========================================================================
    output logic            timeout_timer_en,
    output logic            timer_rst_n,
    input  logic            timeout_8ms_occured,

    // =========================================================================
    // Shared Sideband TX Message Bus (MUX Output)
    // =========================================================================
    output logic            sb_tx_valid,
    output msg_no_e         sb_tx_msg_id,
    output logic [15:0]     sb_tx_MsgInfo,
    output logic [63:0]     sb_tx_data_Field,

    // Sideband RX snoop + FIFO-ready (for TRAINERROR entry handshake, §4.5.3.8)
    input  logic            sb_rx_valid,
    input  msg_no_e         sb_rx_msg_id,
    input  logic            sb_ltsm_rdy,

    // Submodule TX message inputs
    input  logic            sbinit_tx_valid,
    input  msg_no_e         sbinit_tx_msg_id,
    input  logic [15:0]     sbinit_tx_MsgInfo,
    input  logic [63:0]     sbinit_tx_data_Field,

    input  logic            mbinit_tx_valid,
    input  msg_no_e         mbinit_tx_msg_id,
    input  logic [15:0]     mbinit_tx_MsgInfo,
    input  logic [63:0]     mbinit_tx_data_Field,

    input  logic            mbtrain_tx_valid,
    input  msg_no_e         mbtrain_tx_msg_id,
    input  logic [15:0]     mbtrain_tx_MsgInfo,
    input  logic [63:0]     mbtrain_tx_data_Field,

    input  logic            phyretrain_tx_valid,
    input  msg_no_e         phyretrain_tx_msg_id,
    input  logic [15:0]     phyretrain_tx_MsgInfo,
    input  logic [63:0]     phyretrain_tx_data_Field,

    // =========================================================================
    // Mainband Training MUX Outputs
    // =========================================================================
    output logic            mb_tx_pattern_en,
    output logic [2:0]      mb_tx_pattern_setup,
    output logic [1:0]      mb_tx_data_pattern_sel,
    output logic            mb_tx_val_pattern_sel,
    output logic            mb_rx_compare_en,
    output logic [1:0]      mb_rx_compare_setup,
    output logic            clear_error_req,
    output logic            mb_lane_reversal_req,

    // Submodule Mainband inputs
    input  logic            mbinit_mb_tx_pattern_en,
    input  logic [2:0]      mbinit_mb_tx_pattern_setup,
    input  logic [1:0]      mbinit_mb_tx_data_pattern_sel,
    input  logic            mbinit_mb_tx_val_pattern_sel,
    input  logic            mbinit_mb_rx_compare_en,
    input  logic [1:0]      mbinit_mb_rx_compare_setup,
    input  logic            mbinit_clear_error_req,
    input  logic            mbinit_mb_lane_reversal_req,

    input  logic            mbtrain_mb_tx_pattern_en,
    input  logic [2:0]      mbtrain_mb_tx_pattern_setup,
    input  logic [1:0]      mbtrain_mb_tx_data_pattern_sel,
    input  logic            mbtrain_mb_tx_val_pattern_sel,
    input  logic            mbtrain_mb_rx_compare_en,
    input  logic [1:0]      mbtrain_mb_rx_compare_setup,
    input  logic            mbtrain_clear_error_req,
    input  logic            mbtrain_mb_lane_reversal_req,

    // =========================================================================
    // Shared D2C Point Test MUX Interface
    // =========================================================================
    // Outputs to wrapper_D2C_PT
    output logic            local_tx_pt_en,
    output logic            partner_tx_pt_en,
    output logic [2:0]      d2c_pattern_setup,
    output logic [1:0]      d2c_data_pattern_sel,
    output logic            d2c_pattern_mode,
    output logic [1:0]      d2c_compare_setup,

    // D2C controls from MBINIT
    input  logic            mbinit_local_tx_pt_en,
    input  logic            mbinit_partner_tx_pt_en,
    input  logic [2:0]      mbinit_d2c_pattern_setup,
    input  logic [1:0]      mbinit_d2c_data_pattern_sel,
    input  logic            mbinit_d2c_pattern_mode,
    input  logic [1:0]      mbinit_d2c_compare_setup,

    // D2C controls from MBTRAIN
    input  logic            mbtrain_local_tx_pt_en,
    input  logic            mbtrain_partner_tx_pt_en,
    input  logic [2:0]      mbtrain_d2c_pattern_setup,
    input  logic [1:0]      mbtrain_d2c_data_pattern_sel,
    input  logic            mbtrain_d2c_pattern_mode,
    input  logic [1:0]      mbtrain_d2c_compare_setup,

    // =========================================================================
    // Capability Configurations (Static Register Settings)
    // =========================================================================
    input  logic [2:0]      reg_Max_Link_Width_cap,

    // =========================================================================
    // Capability Status Registers (Latching / Freeze MUX outputs)
    // =========================================================================
    output logic            reg_Clock_Phase_enable_status,
    output logic            reg_Clock_mode_enable_status,
    output logic            reg_TARR_enable_status,
    output logic [3:0]      reg_Link_Width_enable_status,
    output logic [3:0]      reg_Link_Speed_enable_status,
    output logic            reg_PMO_enable_status,
    output logic            reg_L2SPD_enable_status,
    output logic            reg_PSPT_enable_status,

    // Submodule capability settings from MBINIT
    input  logic            mbinit_Clock_Phase_enable_status,
    input  logic            mbinit_Clock_mode_enable_status,
    input  logic            mbinit_TARR_enable_status,
    input  logic [3:0]      mbinit_Link_Width_enable_status,
    input  logic [3:0]      mbinit_Link_Speed_enable_status,
    input  logic            mbinit_PMO_enable_status,
    input  logic            mbinit_L2SPD_enable_status,
    input  logic            mbinit_PSPT_enable_status,

    // =========================================================================
    // Status Log Registers (shifted and updated on change)
    // =========================================================================
    input  state_n_e        mbinit_state_n,
    input  state_n_e        mbtrain_state_n,

    output logic [7:0]      log0_state_n,
    output logic            log0_lane_reversal,
    output logic            log0_width_degrade,
    output logic [7:0]      log0_state_n_minus_1,
    output logic [7:0]      log0_state_n_minus_2,
    output logic [7:0]      log1_state_n_minus_3,

    output logic            log0_state_n_valid,
    output logic            log0_lane_reversal_valid,
    output logic            log0_width_degrade_valid,
    output logic            log0_state_n_minus_1_valid,
    output logic            log0_state_n_minus_2_valid,
    output logic            log1_state_n_minus_3_valid,

    output logic            log1_state_timeout_occ,
    output logic            log1_sideband_timeout_occ,
    output logic            log1_remote_link_error,
    output logic            log1_internal_error,

    output logic            log1_state_timeout_occ_valid,
    output logic            log1_sideband_timeout_occ_valid,
    output logic            log1_remote_link_error_valid,
    output logic            log1_internal_error_valid
);

    // =============================================================================
    // STATE REGISTER
    // =============================================================================
    ltsm_ctrl_state_e current_state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= CTRL_RESET;
        else
            current_state <= next_state;
    end

    // =============================================================================
    // TRAINERROR ENTRY HANDSHAKE QUALIFIERS (UCIe 3.0 §4.5.3.8)
    // =============================================================================
    // The sideband is message-capable once SBINIT has completed, i.e. in any
    // state past SBINIT. The spec requires the entry handshake only when the
    // sideband is active and we are leaving a state other than SBINIT; otherwise
    // we drop straight into TRAINERROR (as the controller did historically).
    logic sideband_active;
    assign sideband_active = (current_state != CTRL_RESET) &&
                             (current_state != CTRL_SBINIT);

    // We are inside one of the entry-handshake sub-phases.
    logic in_te_hs;
    assign in_te_hs = (current_state == CTRL_TE_REQ_SEND) ||
                      (current_state == CTRL_TE_REQ_WAIT) ||
                      (current_state == CTRL_TE_RESP_SEND);

    // Local desire to enter TRAINERROR (explicit request / global timeout /
    // per-state error / ACTIVE-resolved TRAINERROR). active_error is excluded
    // on purpose: as before it only feeds the error log, it does not force the
    // transition.
    logic te_local_trigger;
    always_comb begin
        te_local_trigger = (state_req == TRAINERROR) || trainerror_req || timeout_8ms_occured;
        case (current_state)
            CTRL_MBINIT:     if (mbinit_error)                            te_local_trigger = 1'b1;
            CTRL_MBTRAIN:    if (mbtrain_error)                           te_local_trigger = 1'b1;
            CTRL_PHYRETRAIN: if (phyretrain_error)                        te_local_trigger = 1'b1;
            CTRL_ACTIVE:     if (active_next_ltsm_state == CTRL_TRAINERROR) te_local_trigger = 1'b1;
            default: ;
        endcase
    end

    // Partner asked us to enter TRAINERROR (responder role).
    logic te_remote_req;
    assign te_remote_req = sideband_active && sb_rx_valid &&
                           (sb_rx_msg_id == TRAINERROR_Entry_req);

    // RX stickies, accumulated only while handshaking and cleared otherwise.
    logic te_resp_rcvd;    // initiator saw {TRAINERROR Entry resp}
    logic te_req_rcvd_hs;  // collision (Option A): partner also requested while we waited
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            te_resp_rcvd   <= 1'b0;
            te_req_rcvd_hs <= 1'b0;
        end else if (!in_te_hs) begin
            te_resp_rcvd   <= 1'b0;
            te_req_rcvd_hs <= 1'b0;
        end else if (sb_rx_valid) begin
            if (sb_rx_msg_id == TRAINERROR_Entry_resp) te_resp_rcvd   <= 1'b1;
            if (sb_rx_msg_id == TRAINERROR_Entry_req)  te_req_rcvd_hs <= 1'b1;
        end
    end

    // =============================================================================
    // NEXT STATE LOGIC
    // =============================================================================
    always_comb begin
        next_state = current_state;

        case (current_state)
            // -----------------------------------------------------------------
            // TRAINERROR entry handshake sub-phases (§4.5.3.8)
            // -----------------------------------------------------------------
            CTRL_TE_REQ_SEND: begin
                // Initiator: hold {TRAINERROR Entry req} until the SB FIFO accepts.
                if (sb_ltsm_rdy) next_state = CTRL_TE_REQ_WAIT;
            end

            CTRL_TE_REQ_WAIT: begin
                // Enter on {Entry resp}, on a colliding {Entry req} (Option A),
                // or on the 8 ms no-response timeout.
                if (te_resp_rcvd || te_req_rcvd_hs || timeout_8ms_occured)
                    next_state = CTRL_TRAINERROR;
            end

            CTRL_TE_RESP_SEND: begin
                // Responder: hold {TRAINERROR Entry resp} until the SB FIFO accepts.
                if (sb_ltsm_rdy) next_state = CTRL_TRAINERROR;
            end

            CTRL_TRAINERROR: begin
                if (trainerror_done) next_state = CTRL_RESET;
            end

            // -----------------------------------------------------------------
            // Normal states: a TRAINERROR trigger is routed through the
            // handshake when the sideband is active, else taken directly.
            // -----------------------------------------------------------------
            default: begin
                if (te_local_trigger || te_remote_req) begin
                    if (!sideband_active)
                        next_state = CTRL_TRAINERROR;     // RESET/SBINIT: no handshake
                    else if (te_local_trigger)
                        next_state = CTRL_TE_REQ_SEND;    // initiator (wins a collision)
                    else
                        next_state = CTRL_TE_RESP_SEND;   // responder
                end else begin
                    case (current_state)
                        CTRL_RESET:    if (reset_done)   next_state = CTRL_SBINIT;
                        CTRL_SBINIT:   if (sbinit_done)  next_state = CTRL_MBINIT;
                        CTRL_MBINIT:   if (mbinit_done)  next_state = CTRL_MBTRAIN;

                        CTRL_MBTRAIN: begin
                            if      (phyretrain_req) next_state = CTRL_PHYRETRAIN;
                            else if (mbtrain_done)   next_state = CTRL_LINKINIT;
                        end

                        CTRL_LINKINIT: if (linkinit_done) next_state = CTRL_ACTIVE;

                        CTRL_ACTIVE: begin
                            if (active_next_ltsm_state != CTRL_ACTIVE && active_next_ltsm_state != CTRL_NOP) begin
                                next_state = active_next_ltsm_state;
                            end else if (state_req == PHYRETRAIN || phyretrain_req) begin
                                next_state = CTRL_PHYRETRAIN;
                            end else if (state_req == L1) begin
                                next_state = CTRL_L1;
                            end else if (state_req == L2) begin
                                next_state = CTRL_L2;
                            end
                        end

                        CTRL_PHYRETRAIN: if (phyretrain_done) next_state = CTRL_MBTRAIN;

                        CTRL_L1: begin
                            if (state_req == MBTRAIN || mbtrain_speedidle_req) next_state = CTRL_MBTRAIN;
                            else if (state_req == RESET || reset_req)          next_state = CTRL_RESET;
                        end

                        CTRL_L2: begin
                            if (state_req == MBTRAIN || mbtrain_speedidle_req) next_state = CTRL_MBTRAIN;
                            else if (state_req == RESET || reset_req)          next_state = CTRL_RESET;
                        end

                        default: next_state = CTRL_RESET;
                    endcase
                end
            end
        endcase
    end

    // =============================================================================
    // STATE ENABLES
    // =============================================================================
    always_comb begin
        reset_en        = 1'b0;
        sbinit_en       = 1'b0;
        mbinit_en       = 1'b0;
        mbtrain_en      = 1'b0;
        linkinit_en     = 1'b0;
        active_en       = 1'b0;
        phyretrain_en   = 1'b0;
        l1_en           = 1'b0;
        l2_en           = 1'b0;
        trainerror_en   = 1'b0;

        case (current_state)
            CTRL_RESET:      reset_en      = 1'b1;
            CTRL_SBINIT:     sbinit_en     = 1'b1;
            CTRL_MBINIT:     mbinit_en     = 1'b1;
            CTRL_MBTRAIN:    mbtrain_en    = 1'b1;
            CTRL_LINKINIT:   linkinit_en   = 1'b1;
            CTRL_ACTIVE:     active_en     = 1'b1;
            CTRL_PHYRETRAIN: phyretrain_en = 1'b1;
            CTRL_L1:         l1_en         = 1'b1;
            CTRL_L2:         l2_en         = 1'b1;
            CTRL_TRAINERROR: trainerror_en = 1'b1;
            default: ;
        endcase
    end

    // =============================================================================
    // STATE STATUS ENUM MAPPINGS
    // =============================================================================
    always_comb begin
        case (current_state)
            CTRL_RESET:      current_ltsm_state = RESET;
            CTRL_SBINIT:     current_ltsm_state = SBINIT;
            CTRL_MBINIT:     current_ltsm_state = MBINIT;
            CTRL_MBTRAIN:    current_ltsm_state = MBTRAIN;
            CTRL_LINKINIT:   current_ltsm_state = LINKINIT;
            CTRL_ACTIVE:     current_ltsm_state = ACTIVE;
            CTRL_PHYRETRAIN: current_ltsm_state = PHYRETRAIN;
            CTRL_L1:         current_ltsm_state = L1;
            CTRL_L2:         current_ltsm_state = L2;
            CTRL_TRAINERROR: current_ltsm_state = TRAINERROR;
            // The entry-handshake sub-phases are committed to TRAINERROR; expose
            // them as TRAINERROR to the rest of the system.
            CTRL_TE_REQ_SEND,
            CTRL_TE_REQ_WAIT,
            CTRL_TE_RESP_SEND: current_ltsm_state = TRAINERROR;
            default:         current_ltsm_state = NO_OP;
        endcase
    end

    // =============================================================================
    // SHARED WATCHDOG TIMER CONTROL
    // =============================================================================
    assign timeout_timer_en = (current_ltsm_state == SBINIT) ||
                              (current_ltsm_state == MBINIT) ||
                              (current_ltsm_state == MBTRAIN) ||
                              (current_ltsm_state == LINKINIT) ||
                              (current_ltsm_state == PHYRETRAIN) ||
                              in_te_hs; // 8 ms cap on the TRAINERROR entry handshake

    // =============================================================================
    // LINK TRAINING / RETRAINING STATUS (to Register File)
    // =============================================================================
    assign link_training_retraining = (current_ltsm_state == SBINIT) ||
                                      (current_ltsm_state == MBINIT) ||
                                      (current_ltsm_state == MBTRAIN) ||
                                      (current_ltsm_state == LINKINIT) ||
                                      (current_ltsm_state == PHYRETRAIN);

    // =============================================================================
    // LINK STATUS (to Register File)
    // =============================================================================
    assign link_status = (current_ltsm_state == ACTIVE) ||
                         (current_ltsm_state == PHYRETRAIN) ||
                         (current_ltsm_state == L1) ||
                         (current_ltsm_state == L2);

    state_n_e current_log_state;
    logic [4:0] current_log_state_d;
    logic timer_rst_n_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_log_state_d <= LOG_RESET;
            timer_rst_n_reg     <= 1'b0;
        end else begin
            current_log_state_d <= current_log_state;
            if (current_log_state != current_log_state_d) begin
                timer_rst_n_reg <= 1'b0;
            end else begin
                timer_rst_n_reg <= 1'b1;
            end
        end
    end
    assign timer_rst_n = timer_rst_n_reg;

    // =============================================================================
    // SIDEBAND MESSAGE MUX
    // =============================================================================
    always_comb begin
        sb_tx_valid      = 1'b0;
        sb_tx_msg_id     = msg_no_e'(0);
        sb_tx_MsgInfo    = 16'h0;
        sb_tx_data_Field = 64'h0;

        case (current_state)
            CTRL_SBINIT: begin
                sb_tx_valid      = sbinit_tx_valid;
                sb_tx_msg_id     = sbinit_tx_msg_id;
                sb_tx_MsgInfo    = sbinit_tx_MsgInfo;
                sb_tx_data_Field = sbinit_tx_data_Field;
            end
            CTRL_MBINIT: begin
                sb_tx_valid      = mbinit_tx_valid;
                sb_tx_msg_id     = mbinit_tx_msg_id;
                sb_tx_MsgInfo    = mbinit_tx_MsgInfo;
                sb_tx_data_Field = mbinit_tx_data_Field;
            end
            CTRL_MBTRAIN: begin
                sb_tx_valid      = mbtrain_tx_valid;
                sb_tx_msg_id     = mbtrain_tx_msg_id;
                sb_tx_MsgInfo    = mbtrain_tx_MsgInfo;
                sb_tx_data_Field = mbtrain_tx_data_Field;
            end
            CTRL_PHYRETRAIN: begin
                sb_tx_valid      = phyretrain_tx_valid;
                sb_tx_msg_id     = phyretrain_tx_msg_id;
                sb_tx_MsgInfo    = phyretrain_tx_MsgInfo;
                sb_tx_data_Field = phyretrain_tx_data_Field;
            end
            // TRAINERROR entry handshake messages are driven by the controller
            // itself (§4.5.3.8); MsgInfo / data field carry no payload.
            CTRL_TE_REQ_SEND: begin
                sb_tx_valid  = 1'b1;
                sb_tx_msg_id = TRAINERROR_Entry_req;
            end
            CTRL_TE_RESP_SEND: begin
                sb_tx_valid  = 1'b1;
                sb_tx_msg_id = TRAINERROR_Entry_resp;
            end
            default: ;
        endcase
    end

    // =============================================================================
    // MAINBAND TRAINING & COMPARISON MUX
    // =============================================================================
    always_comb begin
        mb_tx_pattern_en       = 1'b0;
        mb_tx_pattern_setup    = 3'b000;
        mb_tx_data_pattern_sel = 2'b00;
        mb_tx_val_pattern_sel  = 1'b0;
        mb_rx_compare_en       = 1'b0;
        mb_rx_compare_setup    = 2'b00;
        clear_error_req        = 1'b0;

        case (current_state)
            CTRL_MBINIT: begin
                mb_tx_pattern_en       = mbinit_mb_tx_pattern_en;
                mb_tx_pattern_setup    = mbinit_mb_tx_pattern_setup;
                mb_tx_data_pattern_sel = mbinit_mb_tx_data_pattern_sel;
                mb_tx_val_pattern_sel  = mbinit_mb_tx_val_pattern_sel;
                mb_rx_compare_en       = mbinit_mb_rx_compare_en;
                mb_rx_compare_setup    = mbinit_mb_rx_compare_setup;
                clear_error_req        = mbinit_clear_error_req;
            end
            CTRL_MBTRAIN: begin
                mb_tx_pattern_en       = mbtrain_mb_tx_pattern_en;
                mb_tx_pattern_setup    = mbtrain_mb_tx_pattern_setup;
                mb_tx_data_pattern_sel = mbtrain_mb_tx_data_pattern_sel;
                mb_tx_val_pattern_sel  = mbtrain_mb_tx_val_pattern_sel;
                mb_rx_compare_en       = mbtrain_mb_rx_compare_en;
                mb_rx_compare_setup    = mbtrain_mb_rx_compare_setup;
                clear_error_req        = mbtrain_clear_error_req;
            end
            default: ;
        endcase
    end

    // =============================================================================
    // LANE REVERSAL REQUEST REGISTER LATCHING
    // =============================================================================
    logic mb_lane_reversal_req_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mb_lane_reversal_req_reg <= 1'b0;
        end else if (current_state == CTRL_RESET) begin
            mb_lane_reversal_req_reg <= 1'b0;
        end else if (current_state == CTRL_MBINIT) begin
            mb_lane_reversal_req_reg <= mbinit_mb_lane_reversal_req;
        end else if (current_state == CTRL_MBTRAIN) begin
            mb_lane_reversal_req_reg <= mbtrain_mb_lane_reversal_req;
        end
    end

    always_comb begin
        mb_lane_reversal_req = mb_lane_reversal_req_reg;
        if (current_state == CTRL_RESET) begin
            mb_lane_reversal_req = 1'b0;
        end else if (current_state == CTRL_MBINIT) begin
            mb_lane_reversal_req = mbinit_mb_lane_reversal_req;
        end else if (current_state == CTRL_MBTRAIN) begin
            mb_lane_reversal_req = mbtrain_mb_lane_reversal_req;
        end
    end

    // (D2C inputs are broadcasted directly in the wrapper, bypassing the controller)

    always_comb begin
        local_tx_pt_en       = 1'b0;
        partner_tx_pt_en     = 1'b0;
        d2c_pattern_setup    = 3'b000;
        d2c_data_pattern_sel = 2'b00;
        d2c_pattern_mode     = 1'b0;
        d2c_compare_setup    = 2'b00;

        case (current_state)
            CTRL_MBINIT: begin
                local_tx_pt_en       = mbinit_local_tx_pt_en;
                partner_tx_pt_en     = mbinit_partner_tx_pt_en;
                d2c_pattern_setup    = mbinit_d2c_pattern_setup;
                d2c_data_pattern_sel = mbinit_d2c_data_pattern_sel;
                d2c_pattern_mode     = mbinit_d2c_pattern_mode;
                d2c_compare_setup    = mbinit_d2c_compare_setup;
            end
            CTRL_MBTRAIN: begin
                local_tx_pt_en       = mbtrain_local_tx_pt_en;
                partner_tx_pt_en     = mbtrain_partner_tx_pt_en;
                d2c_pattern_setup    = mbtrain_d2c_pattern_setup;
                d2c_data_pattern_sel = mbtrain_d2c_data_pattern_sel;
                d2c_pattern_mode     = mbtrain_d2c_pattern_mode;
                d2c_compare_setup    = mbtrain_d2c_compare_setup;
            end
            default: ;
        endcase
    end

    // =============================================================================
    // CAPABILITY STATUS REGISTERS LATCHING / LOOKAHEAD
    // =============================================================================
    logic       reg_Clock_Phase_enable_status_reg;
    logic       reg_Clock_mode_enable_status_reg;
    logic       reg_TARR_enable_status_reg;
    logic [3:0] reg_Link_Width_enable_status_reg;
    logic [3:0] reg_Link_Speed_enable_status_reg;
    logic       reg_PMO_enable_status_reg;
    logic       reg_L2SPD_enable_status_reg;
    logic       reg_PSPT_enable_status_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_Clock_Phase_enable_status_reg <= 1'b0;
            reg_Clock_mode_enable_status_reg  <= 1'b0;
            reg_TARR_enable_status_reg        <= 1'b0;
            reg_Link_Width_enable_status_reg  <= 4'h2; // Default to x16 width
            reg_Link_Speed_enable_status_reg  <= 4'h0;
            reg_PMO_enable_status_reg         <= 1'b0;
            reg_L2SPD_enable_status_reg       <= 1'b0;
            reg_PSPT_enable_status_reg        <= 1'b0;
        end else if (current_state == CTRL_RESET) begin
            reg_Clock_Phase_enable_status_reg <= 1'b0;
            reg_Clock_mode_enable_status_reg  <= 1'b0;
            reg_TARR_enable_status_reg        <= 1'b0;
            reg_Link_Width_enable_status_reg  <= 4'h2;
            reg_Link_Speed_enable_status_reg  <= 4'h0;
            reg_PMO_enable_status_reg         <= 1'b0;
            reg_L2SPD_enable_status_reg       <= 1'b0;
            reg_PSPT_enable_status_reg        <= 1'b0;
        end else if (current_state == CTRL_MBINIT) begin
            // Track submodule values dynamically when inside MBINIT
            reg_Clock_Phase_enable_status_reg <= mbinit_Clock_Phase_enable_status;
            reg_Clock_mode_enable_status_reg  <= mbinit_Clock_mode_enable_status;
            reg_TARR_enable_status_reg        <= mbinit_TARR_enable_status;
            reg_Link_Width_enable_status_reg  <= mbinit_Link_Width_enable_status;
            reg_Link_Speed_enable_status_reg  <= mbinit_Link_Speed_enable_status;
            reg_PMO_enable_status_reg         <= mbinit_PMO_enable_status;
            reg_L2SPD_enable_status_reg       <= mbinit_L2SPD_enable_status;
            reg_PSPT_enable_status_reg        <= mbinit_PSPT_enable_status;
        end
    end

    always_comb begin
        reg_Clock_Phase_enable_status = reg_Clock_Phase_enable_status_reg;
        reg_Clock_mode_enable_status  = reg_Clock_mode_enable_status_reg;
        reg_TARR_enable_status        = reg_TARR_enable_status_reg;
        reg_Link_Width_enable_status  = reg_Link_Width_enable_status_reg;
        reg_Link_Speed_enable_status  = reg_Link_Speed_enable_status_reg;
        reg_PMO_enable_status         = reg_PMO_enable_status_reg;
        reg_L2SPD_enable_status       = reg_L2SPD_enable_status_reg;
        reg_PSPT_enable_status        = reg_PSPT_enable_status_reg;

        if (current_state == CTRL_MBINIT) begin
            reg_Clock_Phase_enable_status = mbinit_Clock_Phase_enable_status;
            reg_Clock_mode_enable_status  = mbinit_Clock_mode_enable_status;
            reg_TARR_enable_status        = mbinit_TARR_enable_status;
            reg_Link_Width_enable_status  = mbinit_Link_Width_enable_status;
            reg_Link_Speed_enable_status  = mbinit_Link_Speed_enable_status;
            reg_PMO_enable_status         = mbinit_PMO_enable_status;
            reg_L2SPD_enable_status       = mbinit_L2SPD_enable_status;
            reg_PSPT_enable_status        = mbinit_PSPT_enable_status;
        end
    end

    // =============================================================================
    // STATE LOG REGISTERS (SHIFT & LATCH HISTORY)
    // =============================================================================
    always_comb begin
        case (current_state)
            CTRL_RESET:      current_log_state = LOG_RESET;
            CTRL_SBINIT:     current_log_state = LOG_SBINIT;
            CTRL_MBINIT:     current_log_state = mbinit_state_n;
            CTRL_MBTRAIN:    current_log_state = mbtrain_state_n;
            CTRL_LINKINIT:   current_log_state = LOG_LINKINIT;
            CTRL_ACTIVE:     current_log_state = LOG_ACTIVE;
            CTRL_PHYRETRAIN: current_log_state = LOG_PHYRETRAIN;
            CTRL_L1, CTRL_L2:current_log_state = LOG_L1_L2;
            CTRL_TRAINERROR: current_log_state = LOG_TRAINERROR;
            // Handshake sub-phases log as TRAINERROR; this also restarts the
            // shared watchdog on entry (fresh 8 ms for the handshake) and avoids
            // a duplicate log shift when CTRL_TRAINERROR is finally reached.
            CTRL_TE_REQ_SEND,
            CTRL_TE_REQ_WAIT,
            CTRL_TE_RESP_SEND: current_log_state = LOG_TRAINERROR;
            default:         current_log_state = LOG_RESET;
        endcase
    end

    logic [7:0] log0_state_n_reg;
    logic [7:0] log0_state_n_minus_1_reg;
    logic [7:0] log0_state_n_minus_2_reg;
    logic [7:0] log1_state_n_minus_3_reg;

    logic log0_state_n_valid_reg;
    logic log0_state_n_minus_1_valid_reg;
    logic log0_state_n_minus_2_valid_reg;
    logic log1_state_n_minus_3_valid_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            log0_state_n_reg         <= 8'h00;
            log0_state_n_minus_1_reg <= 8'h00;
            log0_state_n_minus_2_reg <= 8'h00;
            log1_state_n_minus_3_reg <= 8'h00;

            log0_state_n_valid_reg         <= 1'b0;
            log0_state_n_minus_1_valid_reg <= 1'b0;
            log0_state_n_minus_2_valid_reg <= 1'b0;
            log1_state_n_minus_3_valid_reg <= 1'b0;
        end else begin
            log0_state_n_valid_reg         <= 1'b0;
            log0_state_n_minus_1_valid_reg <= 1'b0;
            log0_state_n_minus_2_valid_reg <= 1'b0;
            log1_state_n_minus_3_valid_reg <= 1'b0;

            if (current_log_state != log0_state_n_reg[4:0]) begin
                log0_state_n_reg         <= {3'b0, current_log_state};
                log0_state_n_minus_1_reg <= log0_state_n_reg;
                log0_state_n_minus_2_reg <= log0_state_n_minus_1_reg;
                log1_state_n_minus_3_reg <= log0_state_n_minus_2_reg;

                log0_state_n_valid_reg         <= 1'b1;
                log0_state_n_minus_1_valid_reg <= 1'b1;
                log0_state_n_minus_2_valid_reg <= 1'b1;
                log1_state_n_minus_3_valid_reg <= 1'b1;
            end
        end
    end

    assign current_ltsm_state_n = current_log_state;

    assign log0_state_n         = log0_state_n_reg;
    assign log0_state_n_minus_1 = log0_state_n_minus_1_reg;
    assign log0_state_n_minus_2 = log0_state_n_minus_2_reg;
    assign log1_state_n_minus_3 = log1_state_n_minus_3_reg;

    assign log0_state_n_valid         = log0_state_n_valid_reg;
    assign log0_state_n_minus_1_valid = log0_state_n_minus_1_valid_reg;
    assign log0_state_n_minus_2_valid = log0_state_n_minus_2_valid_reg;
    assign log1_state_n_minus_3_valid = log1_state_n_minus_3_valid_reg;

    // Dynamically evaluate log0_width_degrade and log0_lane_reversal
    always_comb begin
        log0_width_degrade = 1'b0;
        if (reg_Max_Link_Width_cap == 3'b000) begin // Local max width capability x16
            if (reg_Link_Width_enable_status == 4'h1 || reg_Link_Width_enable_status == 4'h0) begin
                log0_width_degrade = 1'b1;
            end
        end else if (reg_Max_Link_Width_cap == 3'b111) begin // Local max width capability x8
            if (reg_Link_Width_enable_status == 4'h0) begin
                log0_width_degrade = 1'b1;
            end
        end
    end

    assign log0_lane_reversal = mb_lane_reversal_req;

    logic log0_lane_reversal_valid_reg;
    logic log0_width_degrade_valid_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            log0_lane_reversal_valid_reg <= 1'b0;
            log0_width_degrade_valid_reg <= 1'b0;
        end else begin
            log0_lane_reversal_valid_reg <= (next_state != current_state);
            log0_width_degrade_valid_reg <= (next_state != current_state);
        end
    end

    assign log0_lane_reversal_valid = log0_lane_reversal_valid_reg;
    assign log0_width_degrade_valid = log0_width_degrade_valid_reg;

    // =============================================================================
    // ERROR LOG 1 DETAILS
    // =============================================================================
    logic log1_state_timeout_occ_reg;
    logic log1_sideband_timeout_occ_reg;
    logic log1_remote_link_error_reg;
    logic log1_internal_error_reg;

    logic log1_state_timeout_occ_valid_reg;
    logic log1_sideband_timeout_occ_valid_reg;
    logic log1_remote_link_error_valid_reg;
    logic log1_internal_error_valid_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            log1_state_timeout_occ_reg      <= 1'b0;
            log1_sideband_timeout_occ_reg   <= 1'b0;
            log1_remote_link_error_reg      <= 1'b0;
            log1_internal_error_reg         <= 1'b0;

            log1_state_timeout_occ_valid_reg    <= 1'b0;
            log1_sideband_timeout_occ_valid_reg <= 1'b0;
            log1_remote_link_error_valid_reg    <= 1'b0;
            log1_internal_error_valid_reg       <= 1'b0;
        end else begin
            log1_state_timeout_occ_valid_reg    <= 1'b0;
            log1_sideband_timeout_occ_valid_reg <= 1'b0;
            log1_remote_link_error_valid_reg    <= 1'b0;
            log1_internal_error_valid_reg       <= 1'b0;

            // Latch the error cause at the moment we commit to the TRAINERROR
            // path from a normal state — i.e. entering the handshake or, when
            // the sideband is inactive, TRAINERROR directly. The cause signals
            // are no longer asserted once the handshake hands off to TRAINERROR.
            if (!in_te_hs && (current_state != CTRL_TRAINERROR) &&
                (next_state == CTRL_TE_REQ_SEND ||
                 next_state == CTRL_TE_RESP_SEND ||
                 next_state == CTRL_TRAINERROR)) begin
                if (timeout_8ms_occured) begin
                    log1_state_timeout_occ_reg       <= 1'b1;
                    log1_state_timeout_occ_valid_reg <= 1'b1;
                end else if (state_req == TRAINERROR || trainerror_req || te_remote_req) begin
                    log1_remote_link_error_reg       <= 1'b1;
                    log1_remote_link_error_valid_reg <= 1'b1;
                end else if (mbinit_error || mbtrain_error || active_error) begin
                    log1_internal_error_reg       <= 1'b1;
                    log1_internal_error_valid_reg <= 1'b1;
                end
            end
        end
    end

    assign log1_state_timeout_occ          = log1_state_timeout_occ_reg;
    assign log1_sideband_timeout_occ      = log1_sideband_timeout_occ_reg;
    assign log1_remote_link_error          = log1_remote_link_error_reg;
    assign log1_internal_error             = log1_internal_error_reg;

    assign log1_state_timeout_occ_valid    = log1_state_timeout_occ_valid_reg;
    assign log1_sideband_timeout_occ_valid = log1_sideband_timeout_occ_valid_reg;
    assign log1_remote_link_error_valid    = log1_remote_link_error_valid_reg;
    assign log1_internal_error_valid       = log1_internal_error_valid_reg;

    // =============================================================================
    // SYSTEMVERILOG ASSERTIONS & STATE COVERAGE
    // =============================================================================
    `ifdef SIMULATION
        // Safety check: enables are mutually exclusive
        assert_one_hot_enable: assert property (
            @(posedge clk) disable iff (!rst_n)
            $onehot0({reset_en, sbinit_en, mbinit_en, mbtrain_en, linkinit_en, active_en, phyretrain_en, l1_en, l2_en, trainerror_en})
        );
    `endif

endmodule
