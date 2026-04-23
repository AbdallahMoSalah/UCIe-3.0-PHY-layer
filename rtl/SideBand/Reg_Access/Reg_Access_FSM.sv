// ===========================================================================
//  Reg_Access_FSM (Updated based on New Architecture Diagram)
//  Central control unit for the SideBand Register-Access block.
//  * Fully separated from Datapath routing.
//  * Implements Late Address Error Handling.
// ===========================================================================

module Reg_Access_FSM
    import sb_pkg::*; 
(
    input  logic         clk,
    input  logic         rst_n,
    input  logic         phy_in_reset,   // NEW: Indicates PHY is in Link/Soft Reset

    // -----------------------------------------------------------------------
    // Handshake with Top Level / RDI_CONTROL
    // -----------------------------------------------------------------------
    input  logic         reg_vld,        // Valid request from RDI
    output logic         reg_rdy,        // Ready to accept new request
    input  logic         completion_rdy, // TX is ready to accept completion

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
    input  logic         rdata_vld,      // Register file read-data ready
    input  logic         addr_err_o,     // [FIXED SYNTAX]: Address out of range from RF

    // -----------------------------------------------------------------------
    // To Completion_gen
    // -----------------------------------------------------------------------
    output logic [2:0]   status,         // 3'b000=SC, 3'b001=UR
    output logic         completion_start
);

// ---------------------------------------------------------------------------
// State encoding
// ---------------------------------------------------------------------------
typedef enum logic[1:0] {
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
    is_read = opcode inside {
        SB_32_MEM_READ, SB_32_DMS_REG_READ, SB_32_CFG_READ,
        SB_64_MEM_READ, SB_64_DMS_REG_READ, SB_64_CFG_READ
    };
end

// ---------------------------------------------------------------------------
// Error detection (Early Errors ONLY)
// ---------------------------------------------------------------------------
always_comb begin
    //[FIX]: addr_err_o is evaluated later in EXECUTE, so it is removed from here
    error = parity_err || false_msg || ep || phy_in_reset;
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
            if (reg_vld)
                next_state = DECODE;
        end

        DECODE: begin
            // Fast-Forward to GEN if an EARLY error is detected
            if (error)
                next_state = GEN;
            else
                next_state = EXECUTE;
        end

        EXECUTE: begin
            // [FIX]: Exit immediately if Write, OR if Read data is ready,
            // OR if the Register File flagged a Late Address Error (addr_err_o)
            if (!is_read || rdata_vld || addr_err_o)
                next_state = GEN;
        end

        GEN: begin
            if (completion_rdy)
                next_state = IDLE;
        end

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
            reg_rdy = 1'b1; 
        end

        EXECUTE: begin
            rd_en = is_read;
            wr_en = !is_read;
        end

        GEN: begin
            completion_start = 1'b1;
            // [FIX]: Return UR (001) if there was an Early Error OR a Late Address Error
            status = (error || addr_err_o) ? 3'b001 : 3'b000; 
        end

    endcase
end

endmodule