import RDI_SM_pkg::*;
module unit_signal_transition_detector(
    input logic lclk, phyinrecenter, inband_pres, trainerror, clk_handshake_done,
    input RDI_state rdi_state_sts,
    output logic pl_phyinrecenter, pl_inband_pres, pl_trainerror, signal_transition,
    output RDI_state pl_state_sts
);
    
    typedef enum { IDLE, CLK_HANDSHAKE } state;

    state cs;

    always @(posedge lclk) begin
        case (cs)
            IDLE: begin
                if ((phyinrecenter !== pl_phyinrecenter) || 
                    (inband_pres !== pl_inband_pres) || 
                    (trainerror !== pl_trainerror) || 
                    (rdi_state_sts !== pl_state_sts)) begin
                    cs <= CLK_HANDSHAKE;
                end else begin
                    cs <= IDLE;
                end
            end

            CLK_HANDSHAKE: begin
                if (clk_handshake_done) begin
                    cs <= IDLE;
                    pl_phyinrecenter <= phyinrecenter;
                    pl_inband_pres <= inband_pres;
                    pl_trainerror <= trainerror;
                    pl_state_sts <= rdi_state_sts;
                end else begin
                    cs <= CLK_HANDSHAKE;
                end
            end
            default: cs <= IDLE;
        endcase
    end

    assign signal_transition = (cs == CLK_HANDSHAKE);
endmodule