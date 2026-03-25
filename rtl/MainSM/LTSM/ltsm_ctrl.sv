module ltsm_ctrl (
        internal_ltsm_if.ltsm_ctrl2states_mp itf
    );

    import ltsm_state_n_pkg::ltsm_ctrl_state_e;
    import ltsm_state_n_pkg::CTRL_RESET       ;
    import ltsm_state_n_pkg::CTRL_SBINIT      ;
    import ltsm_state_n_pkg::CTRL_MBINIT      ;
    import ltsm_state_n_pkg::CTRL_MBTRAIN     ;
    import ltsm_state_n_pkg::CTRL_LINKINIT    ;
    import ltsm_state_n_pkg::CTRL_ACTIVE      ;
    import ltsm_state_n_pkg::CTRL_PHYRETRAIN  ;
    import ltsm_state_n_pkg::CTRL_L1_L2       ;
    import ltsm_state_n_pkg::CTRL_TRAINERROR  ;

    ltsm_ctrl_state_e current_state, next_state;

    always_ff @(posedge itf.lclk or negedge itf.rst_n) begin
        if (!itf.rst_n) begin
            current_state  <= CTRL_RESET;
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
        if (itf.state_req == CTRL_TRAINERROR || itf.trainerror_req || itf.timeout_8ms_occured) begin
            next_state = CTRL_TRAINERROR;
        end else begin
            case (current_state)
                CTRL_RESET: begin
                    itf.reset_en = 1'b1;
                    if (itf.reset_done) next_state = CTRL_SBINIT;
                    else                next_state = CTRL_RESET;
                end
                CTRL_SBINIT: begin
                    itf.sbinit_en = 1'b1;
                    if (itf.mbinit_done) next_state = CTRL_MBINIT;
                    else                 next_state = CTRL_SBINIT;
                end
                CTRL_MBINIT: begin
                    itf.mbinit_en = 1'b1;
                    if (itf.mbtrain_done) next_state = CTRL_MBTRAIN;
                    else                  next_state = CTRL_MBINIT ;
                end
                CTRL_MBTRAIN: begin
                    itf.mbtrain_en = 1'b1;
                    if (itf.phyretrain_req)    next_state = CTRL_PHYRETRAIN;
                    else if (itf.mbtrain_done) next_state = CTRL_LINKINIT  ;
                    else                       next_state = CTRL_MBTRAIN   ;
                end
                CTRL_LINKINIT: begin
                    itf.linkinit_en = 1'b1;
                    if (itf.linkinit_done) next_state = CTRL_ACTIVE  ;
                    else                   next_state = CTRL_LINKINIT;
                end
                CTRL_ACTIVE: begin
                    itf.active_en = 1'b1; // The ACTIVE state doesn't have done signal.
                    if (itf.state_req == CTRL_PHYRETRAIN || itf.phyretrain_req) next_state = CTRL_PHYRETRAIN;
                    else if (itf.state_req == CTRL_L1_L2)                       next_state = CTRL_L1_L2     ;
                    else                                                        next_state = CTRL_ACTIVE    ;
                end
                CTRL_PHYRETRAIN: begin
                    itf.phyretrain_en = 1'b1;
                    if (itf.phyretrain_done) next_state = CTRL_MBTRAIN   ;
                    else                     next_state = CTRL_PHYRETRAIN;
                end
                CTRL_L1_L2: begin
                    if (itf.state_req == CTRL_MBTRAIN || itf.mbtrain_speedidle_req) next_state = CTRL_MBTRAIN;
                    else if (itf.state_req == CTRL_RESET || itf.reset_req)          next_state = CTRL_RESET;
                    else                                                            next_state = CTRL_L1_L2;
                end
                CTRL_TRAINERROR: begin
                    itf.trainerror_en = 1'b1;
                    if (itf.trainerror_done) next_state = CTRL_RESET     ;
                    else                     next_state = CTRL_TRAINERROR;
                end
                default: next_state = CTRL_RESET;
            endcase
        end
    end
endmodule