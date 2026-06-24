// ===========================================================================
//  Reg_Access_FSM (Updated based on New Architecture Diagram)
//  Central control unit for the SideBand Register-Access block.
//  * Fully separated from Datapath routing.
// ===========================================================================

module Reg_Access_FSM
    import sb_pkg::*; 
(
    input  logic         clk,
    input  logic         rst_n,

    // -----------------------------------------------------------------------
    // Handshake with Top Level / RDI_CONTROL
    // -----------------------------------------------------------------------
    input  logic         reg_vld,        // Valid request from RDI
    output logic         reg_rdy,        // Rdy to accept new request
    input  logic         completion_rdy, // TX is rdy to accept completion

    // -----------------------------------------------------------------------
    // From Reg_DePacketizer (Control Path Only)
    // -----------------------------------------------------------------------
    input  sb_opcode_e   opcode,         // [4:0] Opcode
    input  logic         parity_err,
    input  logic         ep,             // Error Poison
    input  logic         false_msg,

    // -----------------------------------------------------------------------
    // To / From Register File (RF)
    // -----------------------------------------------------------------------
    output logic         rd_en,          // Read enable
    output logic         wr_en,          // Write enable
    input  logic         rdata_vld,      // Register file read-data rdy
    input  logic         rf_addr_err,

    // -----------------------------------------------------------------------
    // To Completion_gen
    // -----------------------------------------------------------------------
    output logic [2:0]   status,         // 3'b000=SC, 3'b001=UR
    output logic         completion_start
);

// ---------------------------------------------------------------------------
// State encoding
// ---------------------------------------------------------------------------
typedef enum logic [1:0] {
    IDLE     = 2'b00,
    DECODE   = 2'b01,
    EXECUTE  = 2'b10,
    GEN      = 2'b11
} state_t;

state_t current_state, next_state;

// Internal signals
logic is_read;
logic error;

// ---------------------------------------------------------------------------
// Opcode classification
// ---------------------------------------------------------------------------
always_comb begin
    is_read = (opcode == SB_32_MEM_READ) || (opcode == SB_32_CFG_READ) || 
              (opcode == SB_64_MEM_READ) || (opcode == SB_64_CFG_READ);
end

// ---------------------------------------------------------------------------
// Error detection (Added Poison 'ep' flag)
// ---------------------------------------------------------------------------
always_comb begin
    error = parity_err || false_msg || ep || rf_addr_err;
end

// ---------------------------------------------------------------------------
// FSM: State Register
// ---------------------------------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        current_state <= IDLE;
    else
        current_state <= next_state;
end

// ---------------------------------------------------------------------------
// FSM: Next-State Logic
// ---------------------------------------------------------------------------
always_comb begin
    next_state = current_state; // Default: stay in current state

    case (current_state)

        IDLE: begin
            // Wait for a valid request
            if (reg_vld)
                next_state = DECODE;
        end

        DECODE: begin
            // Fast-Forward on error to GEN UR response
            if (error)
                next_state = GEN;
            else
                next_state = EXECUTE;
        end

        EXECUTE: begin
            // If it's a WRITE (!is_read), exit immediately.
            // If it's a READ, wait for rdata_vld.
            if (!is_read || rdata_vld)
                next_state = GEN;
        end

        GEN: begin
            // Handshake with completion_gen: wait until it's rdy
            if (completion_rdy)
                next_state = IDLE;
        end

        default: next_state = IDLE;

    endcase
end

// ---------------------------------------------------------------------------
// FSM: Output Logic
// ---------------------------------------------------------------------------
always_comb begin
    // Default values to prevent unwanted latches
    reg_rdy          = 1'b0;
    rd_en            = 1'b0;
    wr_en            = 1'b0;
    completion_start = 1'b0;
    status           = 3'b000;

    case (current_state)

        IDLE: begin
            reg_rdy = 1'b1; // Rdy to receive when idle
        end

        // DECODE: Outputs remain at default (0)

        EXECUTE: begin
            rd_en = is_read;
            wr_en = !is_read;
        end

        GEN: begin
            completion_start = 1'b1;
            // 3'b000 = SC (Success), 3'b001 = UR (Unsupported Request/Error)
            status = error ? 3'b001 : 3'b000; 
        end

        default: ;

    endcase
end

endmodule
