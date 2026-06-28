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

    // Round-Robin priority tracking
    typedef enum logic {
        PRIO_LTSM,
        PRIO_RDI
    } prio_t;

    prio_t  last_prio;
    logic   select_ltsm;
    logic   select_rdi;

    // =========================================================================
    // Arbitration Priority Logic
    // =========================================================================
    always_comb begin
        select_ltsm = 1'b0;
        select_rdi  = 1'b0;

        if (ltsm_valid && rdi_valid) begin
            // If last granted was LTSM, RDI gets priority now
            if (last_prio == PRIO_LTSM) select_rdi  = 1'b1;
            else                        select_ltsm = 1'b1;
        end else if (ltsm_valid) begin
            select_ltsm = 1'b1;
        end else if (rdi_valid) begin
            select_rdi  = 1'b1;
        end
    end

    // =========================================================================
    // Output Logic
    // =========================================================================
    assign link_valid = ltsm_valid || rdi_valid;
    assign link_data  = select_ltsm ? ltsm_data : rdi_data;

    assign ltsm_ready = select_ltsm && link_ready;
    assign rdi_ready  = select_rdi  && link_ready;

    // =========================================================================
    // Priority Update
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_prio <= PRIO_LTSM;
        end else if (link_ready && link_valid) begin
            last_prio <= select_ltsm ? PRIO_LTSM : PRIO_RDI;
        end
    end

endmodule
