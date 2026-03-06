import RDI_SM_pkg::*;
import UCIe_pkg::*;
module unit_sm(
    input logic lclk, lp_link_error, valid_r, clk_handshake_done, stall_done,
    input RDI_state lp_state_req, 
    input logic [4:0]  state_status,
    input msg_no_e Link_Mgmt_Msg_Recieve,
    output logic [4:0] state_req, 
    output msg_no_e Link_Mgmt_Msg_Send,
    output RDI_state pl_state_sts,
    output logic valid_s, stall_req, clk_handshake_strt, trainerror, phyinrecenter, inband_pres
);

    typedef enum logic { Reset, L2, L1, Retrain, Active, Active_PMNAK, LinkReset, Disabled, LinkError  } RDI_state;
    typedef enum logic { IDLE,  LEGAL_TRANSITION, IDLE_from_L1, IDLE_form_Active, Active_handshake} RDI_substate;
    RDI_state cs;
    rdi_substate scs;
    always @(posedge lclk) begin
        case (cs)
            //=========================================================================
            //============================Reset State==================================
            //=========================================================================
            Reset: begin
                case (scs)
                    IDLE: begin
                            if (pl_state_req == NOP)
                                scs <= LEGAL_TRANSITION;
                            end 
                    LEGAL_TRANSITION: begin
                            if (lp_linkerro) begin
                                cs <= LinkError;
                                scs <= IDLE;
                            end else if (pl_state_req == Active) begin//needed to be fixed 
                                cs <= Active;
                                scs <= IDLE;
                            end else if (pl_state_req == LinkReset) begin
                                cs <= LinkReset;
                                scs <= IDLE;
                            end else if (pl_state_req == Disabled) begin
                                cs <= Disabled;
                                scs <= IDLE;
                            end
                    end
                endcase
            end
            //=========================================================================
            //============================L2 State=====================================
            //=========================================================================
            L2: begin
                    if (lp_link_error) begin
                        cs <= LinkError;
                        scs <= IDLE;
                    end
                    else if (lp_state_req == Active) begin
                        cs <= Active;
                        scs <= IDLE;
                    end
            end
            //=========================================================================
            //============================L1 State=====================================
            //=========================================================================
            L1: begin
                    if (lp_link_error) begin
                        cs <= LinkError;
                        scs <= IDLE;
                    end
                    else if (lp_state_req == Active) begin
                        cs <= Retrain;
                        scs <= IDLE_from_L1;
                    end
            end
            //=========================================================================
            //============================Retrain State================================
            //=========================================================================
            Retrain: begin
                case (scs)
                    IDLE_from_L1: begin
                        if (lp_link_error) begin
                            cs <= LinkError;
                            scs <= IDLE;
                        end
                        else if (lp_state_req == Active) begin
                            scs <= Active_handshake;
                        end
                        else if (lp_state_req == LinkReset) begin
                            cs <= LinkReset;
                            scs <= IDLE;
                        end
                        else if (lp_state_req == Disabled) begin
                            cs <= Disabled;
                            scs <= IDLE;
                        end
                    end
                    IDLE_form_Active: begin
                        if (lp_link_error) begin
                            cs <= LinkError;
                            scs <= IDLE;
                        end
                        else if (lp_state_req == Active) begin
                            scs <= Legal_Transition;
                        end
                        else if (lp_state_req == LinkReset) begin
                            cs <= LinkReset;
                            scs <= IDLE;
                        end
                        else if (lp_state_req == Disabled) begin
                            cs <= Disabled;
                            scs <= IDLE;
                        end
                    end
                    Legal_Transition: begin
                        if (lp_link_error) begin
                            cs <= LinkError;
                            scs <= IDLE;
                        end
                        else if (lp_state_req == Active) begin
                            scs <= Active_handshake;
                        end
                    end
                    Active_handshake: begin

                    end
                endcase
            end
            //=========================================================================
            //============================Active State=================================
            //=========================================================================
            Active: begin
                case (scs)
                    IDLE: begin 
                        if (lp_link_error) begin
                        cs <= LinkError;
                        scs <= IDLE;
                        end
                        else if (lp_state_req == L1) begin
                        cs <= L1;
                        scs <= IDLE;
                        end
                        else if (lp_state_req == L2) begin
                        cs <= L2;
                        scs <= IDLE;
                        end 
                        esle if (lp_state_req == LinkReset) begin
                        cs <= LinkReset;    
                        scs <= IDLE;
                        end
                        else if (lp_state_req == Disabled) begin
                        cs <= Disabled;    
                        scs <= IDLE;
                        end
                        else if (lp_state_req == Retrain) begin
                        cs <= Retrain;    
                        scs <= IDLE_form_Active;
                        end
                    end
                endcase
            end
            //=========================================================================
            //============================Active_PMNAK State===========================
            //=========================================================================
            Active_PMNAK: begin
                case (scs)
                   if (lp_link_error) begin
                        cs <= LinkError;
                        scs <= IDLE;
                    end
                    else  if (lp_state_req == Active) begin
                        cs <= Active;
                        scs <= IDLE;
                    end
                    else if (lp_state_req == LinkReset) begin
                        cs <= LinkReset;    
                        scs <= IDLE;
                    end
                    else if (lp_state_req == Disabled) begin
                        cs <= Disabled;    
                        scs <= IDLE;
                    end
                    else if (lp_state_req == Retrain) begin
                        cs <= Retrain;    
                        scs <= IDLE_form_Active;
                    end
                endcase
            end
            //=========================================================================
            //============================LinkReset State==============================
            //=========================================================================
            LinkReset: begin
                case (scs)
                    if (lp_link_error) begin
                            cs <= LinkError;
                            scs <= IDLE;
                    end
                    else if (lp_state_req == Disabled) begin
                            cs <= Disabled;    
                            scs <= IDLE;
                    end
                    else if (lp_state_req == Reset) begin                            
                            cs <= Reset;
                            scs <= IDLE;
                    end
                endcase
            end
            //=========================================================================
            //============================Disabled State===============================
            //=========================================================================
            Disabled: begin
                case (scs)
                    if (lp_link_error) begin
                            cs <= LinkError;
                            scs <= IDLE;
                    end
                    else if (lp_state_req == Reset || lp_state_req == Active) begin                            
                            cs <= Reset;
                            scs <= IDLE;
                    end
                endcase
            end
            //=========================================================================
            //============================LinkError State==============================
            //=========================================================================
            LinkError: begin
                case (scs)
                    if (~lp_linkerror && lp_state_req == Active) begin                            
                            cs <= Reset;
                            scs <= IDLE;
                    end
                endcase
            end
        endcase
    end
    //==============================
    //=======output logic===========
    //============================== 
    assign phyinrecenter = (cs == LinkReset);
    assign inband_pres = (cs == Active);
    assign trainerror = (cs == LinkError);
    assign pl_state_sts = cs;

endmodule