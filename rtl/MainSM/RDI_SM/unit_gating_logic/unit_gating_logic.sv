import RDI_SM_pkg::*;
module unit_gating_logic#(
    parameter int CLK_FREQ = 2_000_000_000  // Default clock frequency: 2GHz
) (
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
    localparam int T1US_LIMIT    = int'(1e-6*real'(CLK_FREQ));
    localparam int COUNTER_WIDTH = $clog2(T1US_LIMIT + 1);
    logic [COUNTER_WIDTH-1:0] counter;

    always_ff @(posedge lclk or negedge rst_n) begin
        if (~rst_n) begin
            GATING_cs <= UNGATING;
            counter   <= '0;
        end
        else
            case (GATING_cs)
                UNGATING:begin
                    if (counter < T1US_LIMIT) begin
                        counter <= counter + 1;
                    end
                    else if (((pl_state_sts == Reset)||    //
                              (pl_state_sts == LinkReset)||
                              (pl_state_sts == Disabled)||
                              (pl_state_sts == L_1)||
                              (pl_state_sts == L_2)) &&
                              ~phyinrecenter &&
                              ~pl_clk_req && 
                              ~ungating_req && 
                              ~inband_pres)begin
                        GATING_cs <= GATING;
                        counter <= 0;
                    end
                    else begin
                        GATING_cs <= UNGATING;
                        counter <= 0;
                    end
                end
            GATING:begin
                if (pl_clk_req||ungating_req || phyinrecenter|| ~((pl_state_sts == Reset)||
                                                                     (pl_state_sts == LinkReset)||  
                                                                     (pl_state_sts == Disabled)||
                                                                     (pl_state_sts == L_1)||
                                                                     (pl_state_sts == L_2))||inband_pres)
                    GATING_cs <= UNGATING;
                else 
                    GATING_cs <= GATING;
            end 
        endcase
    end

assign lclk_g = (GATING_cs == GATING)? 0 : lclk;
assign ungating_done = (GATING_cs == UNGATING);

endmodule