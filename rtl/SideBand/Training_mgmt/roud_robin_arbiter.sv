// =============================================================================
// Module      : RR_arbiter
// Description : A Round-Robin Arbiter with a state machine that manages fair 
//               access between two sources (LTSM and RDI).
//               It includes an IDLE cycle after each grant to ensure 
//               FIFO flags settle, matching the legacy arbiter's timing.
// =============================================================================

module RR_arbiter #(
    parameter DATA_WIDTH = 128
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // -------------------------------------------------------------------------
    // Interface: LTSM FIFO
    // -------------------------------------------------------------------------
    input  logic                     ltsm_valid,
    input  logic [DATA_WIDTH-1:0]    ltsm_data,
    output logic                     ltsm_ready,

    // -------------------------------------------------------------------------
    // Interface: RDI FIFO
    // -------------------------------------------------------------------------
    input  logic                     rdi_valid,
    input  logic [DATA_WIDTH-1:0]    rdi_data,
    output logic                     rdi_ready,

    // -------------------------------------------------------------------------
    // Interface: Link Controller / Packetizer
    // -------------------------------------------------------------------------
    input  logic                     link_ready,
    output logic                     link_valid,
    output logic [DATA_WIDTH-1:0]    link_data
);

    // States for the arbiter FSM
    typedef enum logic [1:0] {
        ST_IDLE,      // Waiting for requests
        ST_GRANT,     // Serving a request
        ST_WAIT_IDLE  // Enforcement of 1-cycle gap
    } state_t;

    // Round-Robin priority tracking
    typedef enum logic {
        PRIO_LTSM,
        PRIO_RDI
    } prio_t;

    state_t current_state, next_state;
    prio_t  last_prio;
    logic   grant_ltsm_win;
    logic   grant_rdi_win;

    // =========================================================================
    // Arbitration Priority Logic
    // =========================================================================
    always_comb begin
        grant_ltsm_win = 1'b0;
        grant_rdi_win  = 1'b0;

        unique case ({ltsm_valid, rdi_valid})
            2'b10: grant_ltsm_win = 1'b1;
            2'b01: grant_rdi_win  = 1'b1;
            2'b11: begin
                // If last granted was LTSM, RDI gets priority now
                if (last_prio == PRIO_LTSM) grant_rdi_win  = 1'b1;
                else                        grant_ltsm_win = 1'b1;
            end
            default: ;
        endcase
    end

    // =========================================================================
    // FSM State Register
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= ST_IDLE;
        else        current_state <= next_state;
    end

    // =========================================================================
    // FSM Next State Logic
    // =========================================================================
    always_comb begin
        next_state = current_state;
        case (current_state)
            ST_IDLE: begin
                if (ltsm_valid || rdi_valid) next_state = ST_GRANT;
            end
            ST_GRANT: begin
                if (link_ready) next_state = ST_WAIT_IDLE;
            end
            ST_WAIT_IDLE: begin
                next_state = ST_IDLE;
            end
            default: next_state = ST_IDLE;
        endcase
    end

    // =========================================================================
    // Output Logic
    // =========================================================================
    logic select_ltsm_q, select_rdi_q;

    // Latch the selection when entering ST_GRANT to ensure data stability
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            select_ltsm_q <= 1'b0;
            select_rdi_q  <= 1'b0;
        end else if (current_state == ST_IDLE && next_state == ST_GRANT) begin
            select_ltsm_q <= grant_ltsm_win;
            select_rdi_q  <= grant_rdi_win;
        end else if (current_state == ST_WAIT_IDLE) begin
            select_ltsm_q <= 1'b0;
            select_rdi_q  <= 1'b0;
        end
    end

    assign link_valid = (current_state == ST_GRANT);
    assign link_data  = select_ltsm_q ? ltsm_data : rdi_data;

    assign ltsm_ready = (current_state == ST_GRANT) && link_ready && select_ltsm_q;
    assign rdi_ready  = (current_state == ST_GRANT) && link_ready && select_rdi_q;

    // =========================================================================
    // Priority Update
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_prio <= PRIO_LTSM;
        end else if (link_ready && link_valid) begin
            last_prio <= select_ltsm_q ? PRIO_LTSM : PRIO_RDI;
        end
    end

endmodule
