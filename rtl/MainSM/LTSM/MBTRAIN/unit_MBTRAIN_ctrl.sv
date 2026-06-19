// ====================================================================================================
// unit_MBTRAIN_ctrl.sv — MBTRAIN Top-Level Sequencer
//
// This module sequences all 13 MBTRAIN sub-states. It follows a unified control
// architecture where each sub-state transition requires BOTH the Local (Initiator)
// and Partner (Responder) FSMs on this die to report completion.
//
// NOTE: Each substate wrapper already combines its local+partner done flags internally
// into a single `*_done` pulse. This controller therefore receives only one done
// signal per substate (not separate local_*_done / partner_*_done).
//
// Each substate wrapper also handles the internal enable fan-out — the controller
// drives a single `*_en` per substate; the wrapper decides which internal FSMs to
// activate. There is therefore no longer a separate local_*_en / partner_*_en here.
//
// Sequence:
//   1. VALVREF         (Rx Valid Lane Vref)
//   2. DATAVREF        (Rx Data Lanes Vref)
//   3. SPEEDIDLE       (Link Speed Negotiation)
//   4. TXSELFCAL       (Tx Self-Calibration)
//   5. RXCLKCAL        (I/Q & Clock Lock)
//   6. VALTRAINCENTER  (Tx Valid PI Centering)
//   7. VALTRAINVREF    (Rx Valid Vref Training)
//   8. DATATRAINCENTER1(Tx Data PI Centering - Pass 1)
//   9. DATATRAINVREF   (Rx Data Vref Training)
//   10. RXDESKEW       (Rx Data Deskew & EQ-Preset Loop)
//   11. DATATRAINCENTER2(Tx Data PI Centering - Pass 2)
//   12. LINKSPEED      (Link Stability Check)
//   13. REPAIR         (Width Degradation)
//
// ====================================================================================================

module unit_MBTRAIN_ctrl (
        // Clock and Reset
        input  logic        lclk,                           // LTSM clock domain
        input  logic        rst_n,                          // Async active-low reset
        input  logic        soft_rst_n,                     // Soft reset (deasserted during RESET/SBINIT)

        // LTSM Interface (to unit_LTSM_ctrl)
        input  logic        mbtrain_en,                     // MBTRAIN state enable
        output logic        mbtrain_done,                   // MBTRAIN state completion
        output ltsm_state_n_pkg::state_n_e  current_mbtrain_substate, // For RF logging / LTSM timeout

        // Global Interrupts / External Requests
        input  logic        trainerror_detected,            // OR of all sub-state trainerror_req outputs
        output logic        ltsm_trainerror_req,            // Request LTSM move to TRAINERROR
        output logic        ltsm_linkinit_req,              // Request LTSM move to LINKINIT
        output logic        ltsm_phyretrain_req,            // Request LTSM move to PHYRETRAIN

        // Entry Requests (from LTSM_ctrl on re-entry)
        input  logic        mbtrain_txselfcal_req,          // Re-enter at TXSELFCAL
        input  logic        mbtrain_speedidle_req,          // Re-enter at SPEEDIDLE
        input  logic        mbtrain_repair_req,             // Re-enter at REPAIR

        // Sub-state Handshakes: VALVREF
        output logic        valvref_en,
        input  logic        valvref_done,

        // Sub-state Handshakes: DATAVREF
        output logic        datavref_en,
        input  logic        datavref_done,

        // Sub-state Handshakes: SPEEDIDLE
        output logic        speedidle_en,
        input  logic        speedidle_done,

        // Sub-state Handshakes: TXSELFCAL
        output logic        txselfcal_en,
        input  logic        txselfcal_done,

        // Sub-state Handshakes: RXCLKCAL
        output logic        rxclkcal_en,
        input  logic        rxclkcal_done,

        // Sub-state Handshakes: VALTRAINCENTER
        output logic        valtraincenter_en,
        input  logic        valtraincenter_done,

        // Sub-state Handshakes: VALTRAINVREF
        output logic        valtrainvref_en,
        input  logic        valtrainvref_done,

        // Sub-state Handshakes: DATATRAINCENTER1
        output logic        dtc1_en,
        input  logic        dtc1_done,

        // Sub-state Handshakes: DATATRAINVREF
        output logic        datatrainvref_en,
        input  logic        datatrainvref_done,

        // Sub-state Handshakes: RXDESKEW
        output logic        rxdeskew_en,
        input  logic        rxdeskew_done,
        input  logic        dtc1_loopback_req,              // From RXDESKEW: loop back to DTC1

        // Sub-state Handshakes: DATATRAINCENTER2
        output logic        dtc2_en,
        input  logic        dtc2_done,

        // Sub-state Handshakes: LINKSPEED
        output logic        linkspeed_en,
        input  logic        linkspeed_done,
        // LINKSPEED routing outputs (fed back to ctrl)
        input  logic        linkspeed_linkinit_req  ,
        input  logic        linkspeed_speedidle_req ,
        input  logic        linkspeed_repair_req    ,
        input  logic        linkspeed_phyretrain_req,

        // Sub-state Handshakes: REPAIR
        output logic        repair_en,
        input  logic        repair_done
    );

    import ltsm_state_n_pkg::*;

    // for current `mbtrain` sub-state
    typedef enum logic [3:0] {
        MBTRAIN_IDLE       = 4'd0,
        VALVREF            = 4'd1,
        DATAVREF           = 4'd2,
        SPEEDIDLE          = 4'd3,
        TXSELFCAL          = 4'd4,
        RXCLKCAL           = 4'd5,
        VALTRAINCENTER     = 4'd6,
        VALTRAINVREF       = 4'd7,
        DATATRAINCENTER1   = 4'd8,
        DATATRAINVREF      = 4'd9,
        RXDESKEW           = 4'd10,
        DATATRAINCENTER2   = 4'd11,
        LINKSPEED          = 4'd12,
        REPAIR             = 4'd13,
        MBTRAIN_DONE       = 4'd14
    } mbtrain_substate_e;
    mbtrain_substate_e current_state, next_state;

    // Registered Routing Requests
    logic reg_linkinit_req, reg_phyretrain_req;

    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            reg_linkinit_req   <= 1'b0;
            reg_phyretrain_req <= 1'b0;
        end
        else if (!soft_rst_n || current_state == MBTRAIN_IDLE) begin
            reg_linkinit_req   <= 1'b0;
            reg_phyretrain_req <= 1'b0;
        end
        else if (current_state == LINKSPEED && linkspeed_done) begin
            reg_linkinit_req   <= linkspeed_linkinit_req;
            reg_phyretrain_req <= linkspeed_phyretrain_req;
        end
    end

    // Assign registered requests to outputs
    assign ltsm_linkinit_req   = reg_linkinit_req;
    assign ltsm_phyretrain_req = reg_phyretrain_req;

    logic is_mbtrain_on;

    // State Register
    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            current_state  <= MBTRAIN_IDLE;
            is_mbtrain_on <= 1'b0;
        end
        else if (!soft_rst_n) begin
            current_state <= MBTRAIN_IDLE;
            is_mbtrain_on <= 1'b0;
        end
        else if(mbtrain_en) begin
            current_state <= next_state;
            is_mbtrain_on <= 1'b1;
        end
        else if(is_mbtrain_on) begin
            current_state <= MBTRAIN_IDLE;
            is_mbtrain_on <= 1'b0;
        end
    end

    // Combinational Next State & Output Logic
    always_comb begin
        // Default Outputs — all enables inactive
        mbtrain_done        = 1'b0;
        next_state          = current_state;
        ltsm_trainerror_req = 1'b0;

        valvref_en        = 1'b0;
        datavref_en       = 1'b0;
        speedidle_en      = 1'b0;
        txselfcal_en      = 1'b0;
        rxclkcal_en       = 1'b0;
        valtraincenter_en = 1'b0;
        valtrainvref_en   = 1'b0;
        dtc1_en           = 1'b0;
        datatrainvref_en  = 1'b0;
        rxdeskew_en       = 1'b0;
        dtc2_en           = 1'b0;
        linkspeed_en      = 1'b0;
        repair_en         = 1'b0;

        // Emergency TRAINERROR Exit
        if (trainerror_detected) begin
            ltsm_trainerror_req = 1'b1;
            next_state          = MBTRAIN_DONE;
            if (current_state == MBTRAIN_DONE) begin
                mbtrain_done = 1'b1;
            end
        end
        else begin
            case (current_state)
                MBTRAIN_IDLE: begin
                    if (mbtrain_en) begin
                        // Entry priority from external requests
                        if      (mbtrain_txselfcal_req) next_state = TXSELFCAL;
                        else if (mbtrain_speedidle_req) next_state = SPEEDIDLE;
                        else if (mbtrain_repair_req)    next_state = REPAIR;
                        else                            next_state = VALVREF;
                    end
                end

                VALVREF: begin
                    valvref_en = 1'b1;
                    if (valvref_done) next_state = DATAVREF;
                end

                DATAVREF: begin
                    datavref_en = 1'b1;
                    if (datavref_done) next_state = SPEEDIDLE;
                end

                SPEEDIDLE: begin
                    speedidle_en = 1'b1;
                    if (speedidle_done) next_state = TXSELFCAL;
                end

                TXSELFCAL: begin
                    txselfcal_en = 1'b1;
                    if (txselfcal_done) next_state = RXCLKCAL;
                end

                RXCLKCAL: begin
                    rxclkcal_en = 1'b1;
                    if (rxclkcal_done) next_state = VALTRAINCENTER;
                end

                VALTRAINCENTER: begin
                    valtraincenter_en = 1'b1;
                    if (valtraincenter_done) next_state = VALTRAINVREF;
                end

                VALTRAINVREF: begin
                    valtrainvref_en = 1'b1;
                    if (valtrainvref_done) next_state = DATATRAINCENTER1;
                end

                DATATRAINCENTER1: begin
                    dtc1_en = 1'b1;
                    if (dtc1_done) next_state = DATATRAINVREF;
                end

                DATATRAINVREF: begin
                    datatrainvref_en = 1'b1;
                    if (datatrainvref_done) next_state = RXDESKEW;
                end

                RXDESKEW: begin
                    rxdeskew_en = 1'b1;
                    // Transition Logic:
                    // 1. Arc loop back to DTC1 takes precedence.
                    // 2. Normal completion moves to DTC2.
                    if (dtc1_loopback_req) begin
                        next_state = DATATRAINCENTER1;
                    end
                    else if (rxdeskew_done) begin
                        next_state = DATATRAINCENTER2;
                    end
                end

                DATATRAINCENTER2: begin
                    dtc2_en = 1'b1;
                    if (dtc2_done) next_state = LINKSPEED;
                end

                LINKSPEED: begin
                    linkspeed_en = 1'b1;
                    if (linkspeed_done) begin
                        // Routing decisions from LINKSPEED (next state only)
                        if (linkspeed_linkinit_req || linkspeed_phyretrain_req) begin
                            next_state = MBTRAIN_DONE;
                        end
                        else if (linkspeed_speedidle_req) begin
                            next_state = SPEEDIDLE;
                        end
                        else if (linkspeed_repair_req) begin
                            next_state = REPAIR;
                        end
                        else begin
                            ltsm_trainerror_req = 1'b1;
                            next_state          = MBTRAIN_DONE;
                        end
                    end
                end

                REPAIR: begin
                    repair_en  = 1'b1;
                    next_state = (repair_done) ? TXSELFCAL : REPAIR;
                end

                MBTRAIN_DONE: begin
                    mbtrain_done = 1'b1;
                    if (!mbtrain_en) next_state = MBTRAIN_IDLE;
                end

                default: next_state = MBTRAIN_IDLE;
            endcase
        end
    end

    // Substate logging for the LTSM error-log register (Table 9-59) and timeout
    // reference. Combinational decode of the *actual* substate so the transcript
    // never flashes a wrong code:
    //   - MBTRAIN_IDLE is a transient entry/exit state with no dedicated log code,
    //     so it anticipates the substate we are about to enter (same priority as
    //     the next_state logic). This avoids logging VALVREF on a SPEEDIDLE/TXSELFCAL
    //     re-entry (e.g. waking from L1).
    //   - MBTRAIN_DONE reports the last completed substate (LINKSPEED) rather than
    //     holding a stale registered value carried over from a previous training pass.
    always_comb begin
        case (current_state)
            MBTRAIN_IDLE    : begin
                if      (mbtrain_txselfcal_req) current_mbtrain_substate = LOG_MBTRAIN_TXSELFCAL;
                else if (mbtrain_speedidle_req) current_mbtrain_substate = LOG_MBTRAIN_SPEEDIDLE;
                else if (mbtrain_repair_req)    current_mbtrain_substate = LOG_MBTRAIN_REPAIR;
                else                            current_mbtrain_substate = LOG_MBTRAIN_VALVREF;
            end
            VALVREF         : current_mbtrain_substate = LOG_MBTRAIN_VALVREF         ;
            DATAVREF        : current_mbtrain_substate = LOG_MBTRAIN_DATAVREF        ;
            SPEEDIDLE       : current_mbtrain_substate = LOG_MBTRAIN_SPEEDIDLE       ;
            TXSELFCAL       : current_mbtrain_substate = LOG_MBTRAIN_TXSELFCAL       ;
            RXCLKCAL        : current_mbtrain_substate = LOG_MBTRAIN_RXCLKCAL        ;
            VALTRAINCENTER  : current_mbtrain_substate = LOG_MBTRAIN_VALTRAINCENTER  ;
            VALTRAINVREF    : current_mbtrain_substate = LOG_MBTRAIN_VALTRAINVREF    ;
            DATATRAINCENTER1: current_mbtrain_substate = LOG_MBTRAIN_DATATRAINCENTER1;
            DATATRAINVREF   : current_mbtrain_substate = LOG_MBTRAIN_DATATRAINVREF   ;
            RXDESKEW        : current_mbtrain_substate = LOG_MBTRAIN_RXDESKEW        ;
            DATATRAINCENTER2: current_mbtrain_substate = LOG_MBTRAIN_DATATRAINCENTER2;
            LINKSPEED       : current_mbtrain_substate = LOG_MBTRAIN_LINKSPEED       ;
            REPAIR          : current_mbtrain_substate = LOG_MBTRAIN_REPAIR          ;
            MBTRAIN_DONE    : current_mbtrain_substate = LOG_MBTRAIN_LINKSPEED       ; // last completed substate
            default         : current_mbtrain_substate = LOG_MBTRAIN_VALVREF         ;
        endcase
    end
endmodule
