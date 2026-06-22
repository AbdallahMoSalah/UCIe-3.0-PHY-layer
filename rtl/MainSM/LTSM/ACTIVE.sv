import RDI_SM_pkg::*;
import ltsm_state_n_pkg::*;
module ACTIVE (
    //Common signals
    input  logic clk,
    input  logic rst_n,
    //local signals
    input  logic active_enable,
    //triggers signals
    input  RDI_state rdi_state, //triggers to PHYRETRAIN,L1,L2,TRAINERROR states
    input  logic Start_UCIe_Link_Training, //triggers to TRAINERROR state
    //output signals
    output logic active_error,
    output ltsm_ctrl_state_e next_ltsm_state
);
    //--------------------------------------
    //edge detector for start_ucie_link_training
    //--------------------------------------
    logic Start_UCIe_Link_Training_edge;
    logic Start_UCIe_Link_Training_d;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            Start_UCIe_Link_Training_d <= 1'b0;
        end else begin
            Start_UCIe_Link_Training_d <= Start_UCIe_Link_Training;
        end
    end
    assign Start_UCIe_Link_Training_edge = Start_UCIe_Link_Training & ~Start_UCIe_Link_Training_d;
    //--------------------------------------

    // ---------------- FSM ----------------
    typedef enum logic [2:0] {
        IDLE,
        ACTIVE_RUN,
        TRAINERROR,
        PHYRETRAIN,
        L1,
        L2
    } active_state_e;

    active_state_e current_state, next_state;
    logic is_linkerror_q;

    // ---------------- State register ----------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state  <= IDLE;
            is_linkerror_q <= 1'b0;
        end else begin
            current_state  <= next_state;
            if (current_state == IDLE) begin
                is_linkerror_q <= 1'b0;
            end else if (current_state == ACTIVE_RUN && next_state == TRAINERROR) begin
                if (rdi_state == LinkError) begin
                    is_linkerror_q <= 1'b1;
                end else begin
                    is_linkerror_q <= 1'b0;
                end
            end
        end
    end

    // ---------------- Next-state logic ----------------
    always_comb begin
        next_state = current_state;
        if (!active_enable) begin
            next_state = IDLE;
        end else begin
            case (current_state)
                IDLE       : next_state = ACTIVE_RUN;
                ACTIVE_RUN : begin
                    if (rdi_state == LinkError || 
                        rdi_state == LinkReset || 
                        rdi_state == Disabled  || 
                        Start_UCIe_Link_Training_edge) next_state = TRAINERROR;
                    else if (rdi_state == L_1) next_state = L1;
                    else if (rdi_state == L_2) next_state = L2;
                    else if (rdi_state == Retrain) next_state = PHYRETRAIN;
                end
                TRAINERROR : ;
                PHYRETRAIN : ;
                L1         : ;
                L2         : ;
                default    : next_state = IDLE;
            endcase
        end
    end

    // ---------------- Output logic ----------------
    always_comb begin 
        active_error = 1'b0;
        next_ltsm_state = CTRL_RESET;
        case (current_state)
            IDLE: begin
                active_error = 1'b0;
                next_ltsm_state = CTRL_RESET;
            end
            ACTIVE_RUN: begin
                active_error = 1'b0;
                next_ltsm_state = CTRL_ACTIVE;
            end
            TRAINERROR: begin
                active_error = is_linkerror_q;
                next_ltsm_state = CTRL_TRAINERROR;
            end
            PHYRETRAIN: begin
                next_ltsm_state = CTRL_PHYRETRAIN;
                active_error = 1'b0;
            end
            L1: begin
                next_ltsm_state = CTRL_L1;
                active_error = 1'b0;
            end
            L2: begin
                next_ltsm_state = CTRL_L2;
                active_error = 1'b0;
            end
            default: begin
                next_ltsm_state = CTRL_RESET;
                active_error = 1'b0;
            end
        endcase
    end
endmodule
