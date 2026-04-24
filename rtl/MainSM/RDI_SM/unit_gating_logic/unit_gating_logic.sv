import RDI_SM_pkg::*;
module unit_gating_logic(
    input  logic lclk,
    input  logic rst_n,
    input  logic inband_pres,
    input  logic phyinrecenter,
    input  logic pl_clk_req,
    input  logic ungating_req,
    input  RDI_state pl_state_sts,
    output logic lclk_g,
    output logic ungating_done
);
    
    typedef enum logic { UNGATING, GATING } state;
    state GATING_cs;
    
    always_ff @(posedge lclk or negedge rst_n) begin
        if (~rst_n)
            GATING_cs <= UNGATING;
        else
            case (GATING_cs)
                UNGATING:begin
                    if (((pl_state_sts == Reset)||(pl_state_sts == LinkReset)||(pl_state_sts == Disabled)||(pl_state_sts == L_1)||(pl_state_sts == L_2)) &&
                        ~phyinrecenter &&
                        ~pl_clk_req && 
                        ~ungating_req && 
                        ~inband_pres)
                        GATING_cs = GATING;
                else 
                    GATING_cs = UNGATING;
            end
            GATING:begin
                if (pl_clk_req||ungating_req || phyinrecenter|| ~((pl_state_sts == Reset)||
                                                                     (pl_state_sts == LinkReset)||
                                                                     (pl_state_sts == Disabled)||
                                                                     (pl_state_sts == L_1)||
                                                                     (pl_state_sts == L_2)))
                    GATING_cs = UNGATING;
                else 
                    GATING_cs = GATING;
            end 
        endcase
    end

assign lclk_g = (GATING_cs == GATING)? 0 : lclk;
assign ungating_done = (GATING_cs == UNGATING);

endmodule