module unit_signal_transition_detector(
    input logic lclk, phyinrecenter, inband_pres, trainerror, clk_handshake_done,
    output logic pl_phyinrecenter, pl_inband_pres, pl_trainerror, signal_transition
);
    
    typedef enum { IDLE, CLK_HANDSHAKE } state;

    state cs;

    always @(posedge lclk) begin
        case (cs)
            IDLE: begin
                if ((phyinrecenter !== pl_phyinrecenter) || 
                    (inband_pres !== pl_inband_pres) || 
                    (trainerror !== pl_trainerror)) begin
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
                end else begin
                    cs <= CLK_HANDSHAKE;
                end
            end
            default: cs <= IDLE;
        endcase
    end

    assign signal_transition = (cs == CLK_HANDSHAKE);
endmodule