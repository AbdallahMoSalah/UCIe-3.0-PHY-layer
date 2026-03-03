import RDI_SM_pkg::*;
module unit_gating_logic(
    input lclk, pl_phyinrecenter, pl_clk_req, ungating_req, 
    input RDI_state pl_state_sts,
    output lclk_g, ungating_done
);
    
    typedef enum bit { UNGATING, GATING } state;
    state GATING_cs;
    
    always @(posedge lclk) begin
        case (GATING_cs)
            UNGATING:begin
                if (((pl_state_sts == Reset)||(pl_state_sts == LinkReset)||(pl_state_sts == Disabled)||(pl_state_sts == L1)||(pl_state_sts == L2)) &&
                    ~pl_phyinrecenter &&
                    ~pl_clk_req && 
                    ~ungating_req)
                    GATING_cs = GATING;
                else 
                    GATING_cs = UNGATING;
            end
            GATING:begin
                if (pl_clk_req||ungating_req || pl_phyinrecenter|| ~((pl_state_sts == Reset)||
                                                                     (pl_state_sts == LinkReset)||
                                                                     (pl_state_sts == Disabled)||
                                                                     (pl_state_sts == L1)||
                                                                     (pl_state_sts == L2)))
                    GATING_cs = UNGATING;
                else 
                    GATING_cs = GATING;
            end 
        endcase
    end

assign lclk_g = (GATING_cs == GATING)? 0 : lclk;
assign ungating_done = (GATING_cs == UNGATING);

endmodule