module unit_MBTRAIN_ctrl (
        internal_ltsm_if.mbtrain_ctrl_mp itf
    );
    import ltsm_state_n_pkg::*;
    // for current `mbtrain` sub-state
    import ltsm_state_n_pkg::mbtrain_substate_e;
    import ltsm_state_n_pkg::MBTRAIN_IDLE      ;
    import ltsm_state_n_pkg::VALVREF           ;
    import ltsm_state_n_pkg::DATAVREF          ;
    import ltsm_state_n_pkg::SPEEDIDLE         ;
    import ltsm_state_n_pkg::TXSELFCAL         ;
    import ltsm_state_n_pkg::RXSELFCAL         ;
    import ltsm_state_n_pkg::VALTRAINCENTER    ;
    import ltsm_state_n_pkg::VALTRAINVREF      ;
    import ltsm_state_n_pkg::DATATRAINCENTER1  ;
    import ltsm_state_n_pkg::DATATRAINVREF     ;
    import ltsm_state_n_pkg::RXDESKEW          ;
    import ltsm_state_n_pkg::DATATRAINCENTER2  ;
    import ltsm_state_n_pkg::LINKSPEED         ;
    import ltsm_state_n_pkg::REPAIR            ;
    import ltsm_state_n_pkg::MBTRAIN_DONE      ;


    mbtrain_substate_e current_state, next_state;

    always_ff @(posedge itf.lclk or negedge itf.rst_n) begin
        if (!itf.rst_n) begin
            current_state <= MBTRAIN_IDLE;
        end
        else if (!itf.is_ltsm_out_of_reset) begin
            current_state <= MBTRAIN_IDLE;
        end
        else begin
            if (!itf.mbtrain_en) begin
                current_state <= MBTRAIN_IDLE;
            end
            else begin
                current_state <= next_state;
            end
        end
    end


    // Combinational FSM: state transitions happen immediately, not waiting for clock edge.
    always_comb begin
        // -----------------------------------------------------------------------
        // Defaults (prevents latches on all outputs)
        // -----------------------------------------------------------------------
        itf.mbtrain_done             = 1'b0;
        itf.current_mbtrain_substate = current_state;
        next_state                   = current_state;

        itf.valvref_en          = 1'b0;
        itf.datavref_en         = 1'b0;
        itf.speedidle_en        = 1'b0;
        itf.txselfcal_en        = 1'b0;
        itf.rxclkcal_en         = 1'b0;
        itf.valtraincenter_en   = 1'b0;
        itf.valtrainvref_en     = 1'b0;
        itf.datatraincenter1_en = 1'b0;
        itf.datatrainvref_en    = 1'b0;
        itf.rxdeskew_en         = 1'b0;
        itf.datatraincenter2_en = 1'b0;
        itf.linkspeed_en        = 1'b0;
        itf.repair_en           = 1'b0;

        // -----------------------------------------------------------------------
        // Normal FSM and Global priority interrupts to TRAINERROR
        // -----------------------------------------------------------------------
        // Reason why trainerror_req can be asserted inside MBTRAIN:
        //   1. Global 8 ms timeout (handled externally by ltsm_ctrl).
        //   2. Receiving a {TRAINERROR Entry req} SB message.
        //   3. VALVREF: fatal — no valid Vref found for the Valid Lane.
        //   4. SPEEDIDLE: entering from LINKSPEED/PHYRETRAIN while already at 4 GT/s.
        //   5. RXCLKCAL: partner TCKN shift out of range after all IQ retries.
        //   6. RXDESKEW: Receiving {MBTRAIN.RXDESKEW exit to DATATRAINCENTER1 req} SB message after 4 arc iterations to DATATRAINCENTER1
        //   7. REPAIR: partner responds with "Degrade not possible".
        // When asserted, hold the current state; ltsm_ctrl will move to TRAINERROR.
        if (itf.trainerror_req) begin
            next_state = (itf.mbtrain_en)? current_state : MBTRAIN_IDLE;
        end
        else begin
            case (current_state)
                // Wait for `ltsm_ctrl` to enable us.
                MBTRAIN_IDLE: begin
                    if (itf.mbtrain_en) begin
                        // Priority check for re-entry requests from LTSM (e.g. from PHYRETRAIN)
                        if (itf.mbtrain_txselfcal_req) next_state = TXSELFCAL;
                        else if (itf.mbtrain_speedidle_req) next_state = SPEEDIDLE;
                        else if (itf.mbtrain_repair_req) next_state = REPAIR;
                        else next_state = VALVREF;
                    end
                end

                // -- Sub-state: VALVREF --
                VALVREF: begin
                    itf.valvref_en = 1'b1;
                    if (itf.valvref_done) next_state = DATAVREF;
                end

                // -- Sub-state: DATAVREF --
                DATAVREF: begin
                    itf.datavref_en = 1'b1;
                    if (itf.datavref_done) next_state = SPEEDIDLE;
                end

                // -- Sub-state: SPEEDIDLE --
                SPEEDIDLE: begin
                    itf.speedidle_en = 1'b1;
                    if (itf.speedidle_done) next_state = TXSELFCAL;
                end

                // -- Sub-state: TXSELFCAL --
                // Also entered after REPAIR (width-degrade) or via mbtrain_txselfcal_req
                // when ltsm_ctrl re-enables MBTRAIN after PHYRETRAIN.
                TXSELFCAL: begin
                    itf.txselfcal_en = 1'b1;
                    if (itf.txselfcal_done) next_state = RXSELFCAL;
                end

                // -- Sub-state: RXCLKCAL --
                RXSELFCAL: begin
                    itf.rxclkcal_en = 1'b1;
                    if (itf.rxclkcal_done) next_state = VALTRAINCENTER;
                end

                // -- Sub-state: VALTRAINCENTER --
                VALTRAINCENTER: begin
                    itf.valtraincenter_en = 1'b1;
                    if (itf.valtraincenter_done) next_state = VALTRAINVREF;
                end

                // -- Sub-state: VALTRAINVREF --
                VALTRAINVREF: begin
                    itf.valtrainvref_en = 1'b1;
                    if (itf.valtrainvref_done) next_state = DATATRAINCENTER1;
                end

                // -- Sub-state: DATATRAINCENTER1 --
                // Also re-entered from RXDESKEW when the EQ-preset loop requires
                // another DTC1 pass (datatraincenter1_req from RXDESKEW sub-FSM).
                DATATRAINCENTER1: begin
                    itf.datatraincenter1_en = 1'b1;
                    if (itf.datatraincenter1_done) next_state = DATATRAINVREF;
                end

                // -- Sub-state: DATATRAINVREF --
                DATATRAINVREF: begin
                    itf.datatrainvref_en = 1'b1;
                    if (itf.datatrainvref_done) next_state = RXDESKEW;
                end

                // -- Sub-state: RXDESKEW --
                // At speeds > 32 GT/s (up to 64 GT/s for our x16 Standard Package),
                // the EQ-preset tuning loop inside the RXDESKEW sub-FSM may request
                // another DATATRAINCENTER1 pass via itf.datatraincenter1_req.
                // Priority: DTC1-loop request beats the sub-state done signal.
                RXDESKEW: begin
                    itf.rxdeskew_en = 1'b1;
                    if      (itf.datatraincenter1_req) next_state = DATATRAINCENTER1;
                    else if (itf.rxdeskew_done)        next_state = DATATRAINCENTER2;
                end

                // -- Sub-state: DATATRAINCENTER2 --
                DATATRAINCENTER2: begin
                    itf.datatraincenter2_en = 1'b1;
                    if (itf.datatraincenter2_done) next_state = LINKSPEED;
                end

                // -- Sub-state: LINKSPEED --
                // Per UCIe spec §4.5.3.4.12 and LTSM_from_MBTRAIN.docx §LINKSPEED:
                //   linkinit_req  → success path  → exit to LINKINIT via MBTRAIN_DONE
                //   phyretrain_req→ Runtime retrain → exit to PHYRETRAIN via MBTRAIN_DONE
                //   speedidle_req → speed-degrade   → re-enter SPEEDIDLE
                //   repair_req   → width-degrade   → enter REPAIR
                // The external req signals are driven by the LINKSPEED sub-state FSM.
                LINKSPEED: begin
                    itf.linkspeed_en = 1'b1;
                    if (itf.linkspeed_done) begin
                        if      (itf.linkinit_req   || itf.phyretrain_req) next_state = MBTRAIN_DONE;
                        else if (itf.speedidle_req)                        next_state = SPEEDIDLE;
                        else if (itf.repair_req)                           next_state = REPAIR;
                    end
                end

                // -- Sub-state: REPAIR --
                REPAIR: begin
                    itf.repair_en = 1'b1;
                    if (itf.repair_done) next_state = TXSELFCAL;
                end

                // -- MBTRAIN_DONE --
                // Assert mbtrain_done to tell ltsm_ctrl to advance to LINKINIT or
                // PHYRETRAIN (the ltsm_ctrl decodes phyretrain_req independently).
                // Stay here until ltsm_ctrl de-asserts mbtrain_en.
                MBTRAIN_DONE: begin
                    itf.mbtrain_done = 1'b1;
                    if (!itf.mbtrain_en) next_state = MBTRAIN_IDLE;
                end

                default: next_state = MBTRAIN_IDLE;
            endcase
        end
    end
endmodule
