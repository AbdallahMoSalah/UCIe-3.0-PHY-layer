module unit_LTSM_ctrl (
        internal_ltsm_if.ltsm_ctrl2states_mp itf
    );

    import LTSM_state_pkg::LTSM_state_e;
    import LTSM_state_pkg::RESET       ;
    import LTSM_state_pkg::SBINIT      ;
    import LTSM_state_pkg::MBINIT      ;
    import LTSM_state_pkg::MBTRAIN     ;
    import LTSM_state_pkg::LINKINIT    ;
    import LTSM_state_pkg::ACTIVE      ;
    import LTSM_state_pkg::PHYRETRAIN  ;
    import LTSM_state_pkg::L1          ;
    import LTSM_state_pkg::L2          ;
    import LTSM_state_pkg::TRAINERROR  ;

    LTSM_state_e current_state, next_state;

    always_ff @(posedge itf.lclk or negedge itf.rst_n) begin
        if (!itf.rst_n) begin
            current_state  <= RESET;
        end else begin
            current_state  <= next_state;
        end
    end

    always_comb begin
        itf.current_ltsm_state = current_state;
        itf.reset_en           = 1'b0         ;
        itf.sbinit_en          = 1'b0         ;
        itf.mbinit_en          = 1'b0         ;
        itf.mbtrain_en         = 1'b0         ;
        itf.linkinit_en        = 1'b0         ;
        itf.active_en          = 1'b0         ;
        itf.phyretrain_en      = 1'b0         ;
        itf.trainerror_en      = 1'b0         ;

        // Global transition to TRAINERROR
        if (itf.state_req == TRAINERROR || itf.trainerror_req || itf.timeout_8ms_occured) begin
            next_state = TRAINERROR;
        end else begin
            case (current_state)
                RESET: begin
                    itf.reset_en = 1'b1;
                    if (itf.reset_done) next_state = SBINIT;
                    else                next_state = RESET;
                end
                SBINIT: begin
                    itf.sbinit_en = 1'b1;
                    if (itf.sbinit_done) next_state = MBINIT;
                    else                 next_state = SBINIT;
                end
                MBINIT: begin
                    itf.mbinit_en = 1'b1;
                    if (itf.mbinit_done) next_state = MBTRAIN;
                    else                  next_state = MBINIT ;
                end
                MBTRAIN: begin
                    itf.mbtrain_en = 1'b1;
                    if (itf.phyretrain_req)    next_state = PHYRETRAIN;
                    else if (itf.mbtrain_done) next_state = LINKINIT  ;
                    else                       next_state = MBTRAIN   ;
                end
                LINKINIT: begin
                    itf.linkinit_en = 1'b1;
                    if (itf.linkinit_done) next_state = ACTIVE  ;
                    else                   next_state = LINKINIT;
                end
                ACTIVE: begin
                    itf.active_en = 1'b1; // The ACTIVE state doesn't have done signal.
                    if (itf.state_req == PHYRETRAIN || itf.phyretrain_req) next_state = PHYRETRAIN;
                    else if (itf.state_req == L1_L2)                       next_state = L1_L2     ;
                    else                                                   next_state = ACTIVE    ;
                end
                PHYRETRAIN: begin
                    itf.phyretrain_en = 1'b1;
                    if (itf.phyretrain_done) next_state = MBTRAIN   ;
                    else                     next_state = PHYRETRAIN;
                end
                L1_L2: begin
                    if (itf.state_req == MBTRAIN || itf.mbtrain_speedidle_req) next_state = MBTRAIN;
                    else if (itf.state_req == RESET || itf.reset_req)          next_state = RESET;
                    else                                                       next_state = L1_L2;
                end
                TRAINERROR: begin
                    itf.trainerror_en = 1'b1;
                    if (itf.trainerror_done) next_state = RESET     ;
                    else                     next_state = TRAINERROR;
                end
                default: next_state = RESET;
            endcase
        end
    end
endmodule
