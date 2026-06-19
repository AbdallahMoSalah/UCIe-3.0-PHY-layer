module L1 
import RDI_SM_pkg::*;
(
    input  logic clk,
    input  logic rst_n,

    input  logic l1_enable,

    input RDI_state rdi_state_sts,
    input RDI_state lp_state_req,   // Requested RDI state from Adapter (wake trigger)

    output logic l1_done,
    output logic l1_error
);

    typedef enum logic [1:0] {
        IDLE,
        L1_RUN,
        LINK_SPEED,
        TRAIN_ERROR
    } l1_state_e;

    l1_state_e current_state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;
        if (!l1_enable) begin
            next_state = IDLE;
        end else begin
            case (current_state)
                IDLE      : next_state = L1_RUN;

                // Wake when the Adapter requests Active again, or a retrain is
                // requested. Exit then routes (in the LTSM controller) into
                // MBTRAIN re-entering at SPEEDIDLE.
                L1_RUN    : if ((lp_state_req == Active) || (rdi_state_sts == Retrain))
                                 next_state = LINK_SPEED;
                            else if (rdi_state_sts == LinkError)
                                 next_state = TRAIN_ERROR;
                
                LINK_SPEED: ;
                TRAIN_ERROR: ;
                default   : next_state = IDLE;
            endcase
        end
    end

    assign l1_done = (current_state == LINK_SPEED);
    assign l1_error = (current_state == TRAIN_ERROR);

endmodule
