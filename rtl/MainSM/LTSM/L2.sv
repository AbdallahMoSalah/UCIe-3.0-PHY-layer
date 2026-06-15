module L2 
import RDI_SM_pkg::*;
(
    input  logic clk,
    input  logic rst_n,

    input  logic l2_enable,

    input RDI_state rdi_state_sts,

    output logic l2_done,
    output logic l2_error
);

    typedef enum logic [1:0] {
        IDLE,
        L2_RUN,
        RESET,
        TRAIN_ERROR
    } l2_state_e;

    l2_state_e current_state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;
        if (!l2_enable) begin
            next_state = IDLE;
        end else begin
            case (current_state)
                IDLE      : next_state = L2_RUN;

                L2_RUN    : if (rdi_state_sts == Reset)
                                 next_state = RESET;
                            else if (rdi_state_sts == LinkError)
                                 next_state = TRAIN_ERROR;
                RESET: ; 
                TRAIN_ERROR: ;
                default   : next_state = IDLE;
            endcase
        end
    end

    assign l2_done = (current_state == RESET);
    assign l2_error = (current_state == TRAIN_ERROR);

endmodule
