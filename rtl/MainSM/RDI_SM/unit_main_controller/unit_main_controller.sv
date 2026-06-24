import RDI_SM_pkg::*;
import LTSM_state_pkg::*;
module unit_main_controller(
    input logic lclk,
    
    input RDI_state Reset_next_state,
    input RDI_state LinkError_next_state,
    input RDI_state Disable_next_state,
    input RDI_state LinkReset_next_state,
    input RDI_state Active_next_state,
    input RDI_state L1_next_state,
    input RDI_state L2_next_state,
    input RDI_state Retrain_next_state,
    input RDI_state Active_PMNAK_next_state,
    input LTSM_state_e state_sts,
    input logic rst_n,

    // message_timeout_handler interface
    input  logic error,                       // block: a SB-message handshake errored
    input  logic handshake_done,              // block: link-error handshake finished
    output logic start_linkerror_handshake,   // ctrl: kick off the link-error handshake
    output logic le_mux_sel,                  // ctrl: give the block the message MUX

    output logic Active_EN,
    output logic L1_EN,
    output logic L2_EN,
    output logic Retrain_EN,
    output logic Active_PMNAK_EN,
    output logic LinkReset_EN,
    output logic Disable_EN,
    output logic Reset_EN,
    output logic LinkError_EN,
    
    output logic trainerror,
    output logic phyinrecenter,
    output logic inband_pres,
    output logic pm_exit,
    output RDI_state rdi_state_sts
);
    // High while the link-error handshake (driven by message_timeout_handler) is
    // in progress: the normal per-state next-state logic is frozen until the
    // block reports handshake_done, after which we force the LinkError state.
    logic le_active;

    assign inband_pres =(((rdi_state_sts == Reset)&&(state_sts == LINKINIT))||
                           (rdi_state_sts == Active)||
                           (rdi_state_sts == Active_PMNAK)||
                           (rdi_state_sts == L_1)||
                           (rdi_state_sts == L_2)||
                           (rdi_state_sts == Retrain));
    // pl_trainerror is asserted whenever the link is in LinkError (regardless of
    // whether it was entered via an LTSM training error or an adapter/peer link
    // error) and clears on the exit to Reset.  This matches assertion A12.
    assign trainerror =(rdi_state_sts == LinkError);
    assign pm_exit = (rdi_state_sts == L_1 || rdi_state_sts == L_2);
    assign phyinrecenter = (state_sts == SBINIT 
                            || state_sts == MBINIT 
                            || state_sts == MBTRAIN 
                            || state_sts == PHYRETRAIN);
    always @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            Active_EN <= 1'b0;
            L1_EN <= 1'b0;
            L2_EN <= 1'b0;
            Retrain_EN <= 1'b0;
            Active_PMNAK_EN <= 1'b0;
            LinkReset_EN <= 1'b0;
            Disable_EN <= 1'b0;
            Reset_EN <= 1'b1; // Start in Reset
            LinkError_EN <= 1'b0;
            rdi_state_sts <= Reset;
            le_active <= 1'b0;
            start_linkerror_handshake <= 1'b0;
            le_mux_sel <= 1'b0;
        end else if (le_active) begin
            // ----------------------------------------------------------------
            // Link-error handshake in progress.  Hold the block's start/MUX
            // grant and freeze all state transitions until the block finishes,
            // then disable every state and enter LinkError.
            // ----------------------------------------------------------------
            start_linkerror_handshake <= 1'b1;
            le_mux_sel                <= 1'b1;
            if (handshake_done) begin
                le_active                 <= 1'b0;
                start_linkerror_handshake <= 1'b0;
                le_mux_sel                <= 1'b0;
                Active_EN       <= 1'b0;
                L1_EN           <= 1'b0;
                L2_EN           <= 1'b0;
                Retrain_EN      <= 1'b0;
                Active_PMNAK_EN <= 1'b0;
                LinkReset_EN    <= 1'b0;
                Disable_EN      <= 1'b0;
                Reset_EN        <= 1'b0;
                LinkError_EN    <= 1'b1;
                rdi_state_sts   <= LinkError;
            end
        end else if (error && (rdi_state_sts != LinkError)) begin
            // Block flagged a sideband-message handshake error: arm the
            // link-error handshake and hand the MUX to the block.
            le_active                 <= 1'b1;
            start_linkerror_handshake <= 1'b1;
            le_mux_sel                <= 1'b1;
        end else begin

        if ((state_sts == TRAINERROR )&&
            (rdi_state_sts != LinkError)) begin
            LinkError_EN <= 1'b1;
            Retrain_EN <= 1'b0;
            Active_EN <= 1'b0;
            L1_EN <= 1'b0;
            L2_EN <= 1'b0;
            Active_PMNAK_EN <= 1'b0;
            LinkReset_EN <= 1'b0;
            Disable_EN <= 1'b0;
            Reset_EN <= 1'b0;
            rdi_state_sts <= LinkError;
        end

        case(rdi_state_sts)
            Reset:begin
                Reset_EN <= 1'b1;
                Active_EN <= 1'b0;
                L1_EN <= 1'b0;
                L2_EN <= 1'b0;
                Retrain_EN <= 1'b0;
                Active_PMNAK_EN <= 1'b0;
                LinkReset_EN <= 1'b0;
                Disable_EN <= 1'b0;
                LinkError_EN <= 1'b0;
                rdi_state_sts <= Reset;

                if (Reset_next_state == Active) begin
                    Reset_EN <= 1'b0;
                    Active_EN <= 1'b1;
                    rdi_state_sts <= Active;
                end
                else if (Reset_next_state == LinkError) begin
                    Reset_EN <= 1'b0;
                    LinkError_EN <= 1'b1;
                    rdi_state_sts <= LinkError;
                end
                else if (Reset_next_state == Disabled) begin
                    Reset_EN <= 1'b0;
                    Disable_EN <= 1'b1;
                    rdi_state_sts <= Disabled;
                end
                else if (Reset_next_state == LinkReset) begin
                    Reset_EN <= 1'b0;
                    LinkReset_EN <= 1'b1;
                    rdi_state_sts <= LinkReset;
                end
            end

            LinkError:begin
                LinkError_EN <= 1'b1;
                Active_EN <= 1'b0;
                L1_EN <= 1'b0;
                L2_EN <= 1'b0;
                Retrain_EN <= 1'b0;
                Active_PMNAK_EN <= 1'b0;
                LinkReset_EN <= 1'b0;
                Disable_EN <= 1'b0;
                Reset_EN <= 1'b0;
                rdi_state_sts <= LinkError;
                if (LinkError_next_state == Reset) begin
                    LinkError_EN <= 1'b0;
                    Reset_EN <= 1'b1;
                    rdi_state_sts <= Reset;
                end

            end
            Disabled:begin
                Disable_EN <= 1'b1;
                Active_EN <= 1'b0;
                L1_EN <= 1'b0;
                L2_EN <= 1'b0;
                Retrain_EN <= 1'b0;
                Active_PMNAK_EN <= 1'b0;
                LinkReset_EN <= 1'b0;
                LinkError_EN <= 1'b0;
                Reset_EN <= 1'b0;
                rdi_state_sts <= Disabled;
                if (Disable_next_state == LinkError) begin
                    Disable_EN <= 1'b0;
                    LinkError_EN <= 1'b1;
                    rdi_state_sts <= LinkError;
                end
                else if (Disable_next_state == Reset) begin
                    Disable_EN <= 1'b0;
                    Reset_EN <= 1'b1;
                    rdi_state_sts <= Reset;
                end
            end
            LinkReset:begin
                LinkReset_EN <= 1'b1;
                Active_EN <= 1'b0;
                L1_EN <= 1'b0;
                L2_EN <= 1'b0;
                Retrain_EN <= 1'b0;
                Active_PMNAK_EN <= 1'b0;
                LinkError_EN <= 1'b0;
                Disable_EN <= 1'b0;
                Reset_EN <= 1'b0;
                rdi_state_sts <= LinkReset;
                if (LinkReset_next_state == LinkError) begin
                    LinkReset_EN <= 1'b0;
                    LinkError_EN <= 1'b1;
                    rdi_state_sts <= LinkError;
                end
                else if (LinkReset_next_state == Disabled) begin
                    LinkReset_EN <= 1'b0;
                    Disable_EN <= 1'b1;
                    rdi_state_sts <= Disabled;
                end
                else if (LinkReset_next_state == Reset) begin
                    LinkReset_EN <= 1'b0;
                    Reset_EN <= 1'b1;
                    rdi_state_sts <= Reset;
                end
            end
            Active:begin
                Active_EN <= 1'b1;
                L1_EN <= 1'b0;
                L2_EN <= 1'b0;
                Retrain_EN <= 1'b0;
                Active_PMNAK_EN <= 1'b0;
                LinkReset_EN <= 1'b0;
                LinkError_EN <= 1'b0;
                Disable_EN <= 1'b0;
                Reset_EN <= 1'b0;
                rdi_state_sts <= Active;
                if (Active_next_state == LinkError) begin
                    Active_EN <= 1'b0;
                    LinkError_EN <= 1'b1;
                    rdi_state_sts <= LinkError;
                end
                else if (Active_next_state == Disabled) begin
                    Active_EN <= 1'b0;
                    Disable_EN <= 1'b1;
                    rdi_state_sts <= Disabled;
                end
                else if (Active_next_state == L_1) begin
                    Active_EN <= 1'b0;
                    L1_EN <= 1'b1;
                    rdi_state_sts <= L_1;
                end
                else if (Active_next_state == L_2) begin
                    Active_EN <= 1'b0;
                    L2_EN <= 1'b1;
                    rdi_state_sts <= L_2;
                end
                else if (Active_next_state == Retrain) begin
                    Active_EN <= 1'b0;
                    Retrain_EN <= 1'b1;
                    rdi_state_sts <= Retrain;
                end
                else if (Active_next_state == Active_PMNAK) begin
                    Active_EN <= 1'b0;
                    Active_PMNAK_EN <= 1'b1;
                    rdi_state_sts <= Active_PMNAK;
                end
                else if (Active_next_state == LinkReset) begin
                    Active_EN <= 1'b0;
                    LinkReset_EN <= 1'b1;
                    rdi_state_sts <= LinkReset;
                end
            end
            L_1:begin
                L1_EN <= 1'b1;
                Active_EN <= 1'b0;
                L2_EN <= 1'b0;
                Retrain_EN <= 1'b0;
                Active_PMNAK_EN <= 1'b0;
                LinkReset_EN <= 1'b0;
                LinkError_EN <= 1'b0;
                Disable_EN <= 1'b0;
                Reset_EN <= 1'b0;
                rdi_state_sts <= L_1;
                
                if (L1_next_state == LinkError) begin
                    L1_EN <= 1'b0;
                    LinkError_EN <= 1'b1;
                    rdi_state_sts <= LinkError;
                end
                else if (L1_next_state == Disabled) begin
                    L1_EN <= 1'b0;
                    Disable_EN <= 1'b1;
                    rdi_state_sts <= Disabled;
                end
                else if (L1_next_state == Retrain) begin
                    L1_EN <= 1'b0;
                    Retrain_EN <= 1'b1;
                    rdi_state_sts <= Retrain;
                end
                else if (L1_next_state == LinkReset) begin
                    L1_EN <= 1'b0;
                    LinkReset_EN <= 1'b1;
                    rdi_state_sts <= LinkReset;
                end
            end
            L_2:begin
                L2_EN <= 1'b1;
                Active_EN <= 1'b0;
                L1_EN <= 1'b0;
                Retrain_EN <= 1'b0;
                Active_PMNAK_EN <= 1'b0;
                LinkReset_EN <= 1'b0;
                LinkError_EN <= 1'b0;
                Disable_EN <= 1'b0;
                Reset_EN <= 1'b0;
                rdi_state_sts <= L_2;
                
                if (L2_next_state == LinkError) begin
                    L2_EN <= 1'b0;
                    LinkError_EN <= 1'b1;
                    rdi_state_sts <= LinkError;
                end
                else if (L2_next_state == Disabled) begin
                    L2_EN <= 1'b0;
                    Disable_EN <= 1'b1;
                    rdi_state_sts <= Disabled;
                end
                else if (L2_next_state == LinkReset) begin
                    L2_EN <= 1'b0;
                    LinkReset_EN <= 1'b1;
                    rdi_state_sts <= LinkReset;
                end
                else if (L2_next_state == Reset) begin
                    L2_EN <= 1'b0;
                    Reset_EN <= 1'b1;
                    rdi_state_sts <= Reset;
                end
            end
            Retrain:begin
                Retrain_EN <= 1'b1;
                Active_EN <= 1'b0;
                L1_EN <= 1'b0;
                L2_EN <= 1'b0;
                Active_PMNAK_EN <= 1'b0;
                LinkReset_EN <= 1'b0;
                LinkError_EN <= 1'b0;
                Disable_EN <= 1'b0;
                Reset_EN <= 1'b0;
                rdi_state_sts <= Retrain;
                if (Retrain_next_state == Active) begin
                    Retrain_EN <= 1'b0;
                    Active_EN <= 1'b1;
                    rdi_state_sts <= Active;
                end
                else if (Retrain_next_state == LinkError) begin
                    Retrain_EN <= 1'b0;
                    LinkError_EN <= 1'b1;
                    rdi_state_sts <= LinkError;
                end
                else if (Retrain_next_state == Disabled) begin
                    Retrain_EN <= 1'b0;
                    Disable_EN <= 1'b1;
                    rdi_state_sts <= Disabled;
                end
                else if (Retrain_next_state == LinkReset) begin
                    Retrain_EN <= 1'b0;
                    LinkReset_EN <= 1'b1;
                    rdi_state_sts <= LinkReset;
                end
            end
            Active_PMNAK:begin
                Active_PMNAK_EN <= 1'b1;
                Active_EN <= 1'b0;
                L1_EN <= 1'b0;
                L2_EN <= 1'b0;
                Retrain_EN <= 1'b0;
                LinkReset_EN <= 1'b0;
                LinkError_EN <= 1'b0;
                Disable_EN <= 1'b0;
                Reset_EN <= 1'b0;
                rdi_state_sts <= Active_PMNAK;
                if (Active_PMNAK_next_state == Active) begin
                    Active_PMNAK_EN <= 1'b0;
                    Active_EN <= 1'b1;
                    rdi_state_sts <= Active;
                end
                else if (Active_PMNAK_next_state == LinkError) begin
                    Active_PMNAK_EN <= 1'b0;
                    LinkError_EN <= 1'b1;
                    rdi_state_sts <= LinkError;
                end
                else if (Active_PMNAK_next_state == Disabled) begin
                    Active_PMNAK_EN <= 1'b0;
                    Disable_EN <= 1'b1;
                    rdi_state_sts <= Disabled;
                end
                else if (Active_PMNAK_next_state == Retrain) begin
                    Active_PMNAK_EN <= 1'b0;
                    Retrain_EN <= 1'b1;
                    rdi_state_sts <= Retrain;
                end
                else if (Active_PMNAK_next_state == LinkReset) begin
                    Active_PMNAK_EN <= 1'b0;
                    LinkReset_EN <= 1'b1;
                    rdi_state_sts <= LinkReset;
                end
            end 
        endcase
    end
    end
endmodule
