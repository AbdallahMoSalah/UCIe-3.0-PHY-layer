// ===========================================================================
//  Reg_Access_FSM
//  Central controller for the SideBand Register-Access block
//
//  UCIe §7.1.1 – "All register accesses (Reads or Writes) have an associated
//  completion."
//
//  State machine (matches reg_access_fsm.png in docs/SB/):
//
//   ┌────────┐  sb_rx_vld==1   ┌────────┐
//   │  IDLE  │───────────────► │ DECODE │
//   └────────┘                 └───┬────┘
//       ▲                            │ error==1          error==0
//       │                            ▼                    ▼
//       │                       ┌──────────┐         ┌─────────┐
//       │  rdata_vld==1         │ GENERATE │◄────────│ EXECUTE │◄─ rdata_vld==0
//       └───────────────────────┤          │         └─────────┘
//                               └──────────┘
//
//  IDLE    : Waits for a valid register-access packet
//  DECODE  : Checks parity and opcode validity (1 cycle)
//  EXECUTE : Issues rd_en or wr_en to Register File; waits for rdata_vld
//  GENERATE: Kicks Completion_gen; returns to IDLE
// ===========================================================================

module Reg_Access_FSM
    import sb_pkg::*;
(
    input  logic         clk,
    input  logic         rst_n,

    // -----------------------------------------------------------------------
    // From Reg_DePacketizer
    // -----------------------------------------------------------------------
    input  sb_opcode_e   opcode,
    input  logic [23:0]  rf_addr,
    input  logic [7:0]   rf_be,
    input  logic [63:0]  rf_wdata,
    input  logic [63:0]  Original_Header,
    input  logic         parity_err,
    input  logic         ep,
    input  logic         false_msg,
    input  logic         reg_vld,    // valid strobe from upstream

    // -----------------------------------------------------------------------
    // To / From Register File
    // UCIe §9.5 – PHY Register Block accessed via rf_addr
    // -----------------------------------------------------------------------
    output logic [23:0]  rf_addr_o,   // Wire-through to register file
    output logic [7:0]   rf_be_o,
    output logic [63:0]  rf_wdata_o,
    output logic         rd_en,       // Read enable
    output logic         wr_en,       // Write enable

    input  logic         rdata_vld,   // Register file read-data ready
    // (write completes in 1 cycle; read may take several)

    // -----------------------------------------------------------------------
    // To Completion_gen
    // UCIe §7.1.1.2 – completion must mirror tag+srcid+dstid of request
    // -----------------------------------------------------------------------
    output logic [2:0]   status,      // 3'b000=SC, 3'b001=UR
    output logic         completion_start
);

// ---------------------------------------------------------------------------
// State encoding
// ---------------------------------------------------------------------------
typedef enum logic [1:0] {
    IDLE     = 2'b00,
    DECODE   = 2'b01,
    EXECUTE  = 2'b10,
    GENERATE = 2'b11
} state_t;

state_t current_state, next_state;

// Internal
logic is_read;
logic error;      // Combinatorial error flag fed to state transition

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
// Error detection (DECODE state evaluation)
// UCIe §7.1.1: parity mismatch or unrecognised opcode → UR completion
// UCIe §7.1.1: "false_msg" = opcode is not a register-access type at all
// ---------------------------------------------------------------------------
always_comb begin
    error = parity_err || false_msg;
end

// ---------------------------------------------------------------------------
// FSM: state register
// ---------------------------------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        current_state <= IDLE;
    else
        current_state <= next_state;
end

// ---------------------------------------------------------------------------
// FSM: next-state logic
// ---------------------------------------------------------------------------
always_comb begin
    next_state = current_state;

    case (current_state)

        IDLE: begin
            // UCIe §7.1.1: wait for valid packet
            if (reg_vld)
                next_state = DECODE;
        end

        DECODE: begin
            // One-cycle decode; any error skips EXECUTE and goes straight
            // to GENERATE (which will issue an UR completion)
            if (error)
                next_state = GENERATE;
            else
                next_state = EXECUTE;
        end

        EXECUTE: begin
            // For writes the register file acknowledges in 1 cycle (rdata_vld
            // from write path is asserted the next cycle).
            // For reads the register file may take several cycles to return
            // data (e.g. if it comes from a flop with a read-enable pipe).
            // UCIe §7 does not impose a maximum latency for internal access.
            if (rdata_vld)
                next_state = GENERATE;
            // else stay in EXECUTE
        end

        GENERATE: begin
            // One-cycle pulse; return to IDLE so next packet can be accepted
            next_state = IDLE;
        end

    endcase
end

// ---------------------------------------------------------------------------
// FSM: output logic
// ---------------------------------------------------------------------------
always_comb begin
    // Defaults – no register-file traffic, no completion
    rd_en             = 1'b0;
    wr_en             = 1'b0;
    completion_start  = 1'b0;
    status            = 3'b000;  // Successful Completion (SC) by default
    rf_addr_o         = rf_addr;
    rf_be_o           = rf_be;
    rf_wdata_o        = rf_wdata;

    case (current_state)

        EXECUTE: begin
            // Drive register-file interface
            // UCIe §9.5 – all PHY configuration registers reside at
            // offsets 1000h–10FFh in the PHY register block.
            rd_en = is_read;
            wr_en = !is_read;
        end

        GENERATE: begin
            completion_start = 1'b1;
            // Status determination:
            // UCIe §7.1.1.2 Table 7-7 status field:
            //   3'b000 – Successful Completion (SC)
            //   3'b001 – Unsupported Request (UR) – invalid opcode / parity
            status = error ? 3'b001 : 3'b000;
        end

        default: ;  // IDLE, DECODE: all outputs default

    endcase
end

endmodule
