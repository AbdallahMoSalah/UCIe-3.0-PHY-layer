// UCIe 3.0 §4.5.3.1 RESET state.
//
// On every entry: serve >= 4 ms minimum dwell, then wait for a link-training
// trigger; once seen, hold RESET_state_done high until RESET_enable deasserts.
//
// Management Transport / Sideband Mgmt-path triggers are intentionally
// omitted (project does not support Mgmt Transport).
//
// All "Tx tri-stated / SB Tx held low / SB Rx enabled" state-level outputs
// are hard-wired by the top LTSM module, not by this block.

module RESET #(
    parameter int CLK_FRQ_HZ = 800000000
) (
    input  logic clk,
    input  logic rst_n,

    // Link-training triggers (UCIe 3.0 §4.5).
    input  logic phy_start_ucie_link_training_ctrl_out,
    input  logic Adapter_training_req,
    input  logic sb_det_pattern_rcvd,

    input  logic RESET_enable,        // High while LTSM is in RESET state.
    output logic RESET_state_done     // Held high once 4-ms dwell + trigger
                                      // both satisfied, until RESET_enable drops.
);

    // ---------------- 4 ms dwell timer ----------------
    logic timer_enable;
    logic RESET_4ms_done;

    timeout_counter #(
        .CLK_FRQ_HZ(CLK_FRQ_HZ),
        .TIME_OUT  (4)
    ) reset_4ms_counter (
        .clk            (clk),
        .timeout_rst_n  (rst_n),
        .enable_timeout (timer_enable),
        .timeout_expired(RESET_4ms_done)
    );

    // ---------------- FSM ----------------
    typedef enum logic [1:0] {
        IDLE,
        DWELL_4MS,
        WAIT_TRIGGER,
        DONE_HOLD
    } reset_state_e;

    reset_state_e current_state, next_state;

    // Triggers can be single-cycle pulses (notably sb_det_pattern_rcvd).
    // Latch each one as a sticky while RESET_enable is high so a pulse arriving
    // during the 4 ms dwell is not lost; cleared whenever the FSM is in IDLE.
    logic trigger_seen;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trigger_seen <= 1'b0;
        end else if (current_state == IDLE) begin
            trigger_seen <= 1'b0;
        end else begin
            if(phy_start_ucie_link_training_ctrl_out || Adapter_training_req || sb_det_pattern_rcvd) begin 
                trigger_seen <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;
        if (!RESET_enable) begin
            next_state = IDLE;
        end else begin
            case (current_state)
                IDLE         : next_state = DWELL_4MS;
                DWELL_4MS    : begin 
                    if (RESET_4ms_done)begin
                        if(trigger_seen)begin
                            next_state = DONE_HOLD;
                        end
                        else begin
                            next_state = WAIT_TRIGGER;
                        end
                    end
                end
                WAIT_TRIGGER : if (trigger_seen)   next_state = DONE_HOLD;
                DONE_HOLD    : ; // hold until RESET_enable drops
                default      : next_state = IDLE;
            endcase
        end
    end

    assign timer_enable     = (current_state == DWELL_4MS);
    assign RESET_state_done = (current_state == DONE_HOLD);

endmodule
