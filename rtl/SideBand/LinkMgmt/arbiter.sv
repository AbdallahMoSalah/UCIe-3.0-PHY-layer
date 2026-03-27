// ============================================================================
// Module Name: arbiter
// Description: Round-Robin Arbiter for Link Management Unit.
//              Arbitrates between RDI and LTSM message FIFOs to send data
//              to the Main Link Controller. Implements flow control using
//              the LINK_ready handshake signal.
// ============================================================================

module arbiter (
    // System Signals
    input  logic         clk,
    input  logic         reset_n,

    // Main Controller Interface (Handshake)
    input  logic         LINK_ready,      // Backpressure from Main Controller 
    output logic [127:0] LINK_msg,        // Outgoing link message 
    output logic         LINK_msg_valid,  // Valid signal for the outgoing link message 

    // RDI FIFO Interface
    input  logic [127:0] rdi_msg_fifo,    // RDI message data 
    input  logic         rdi_not_empty,   // RDI FIFO valid (not empty) 
    output logic         rdi_pop,         // Read enable to RDI FIFO 

    // LTSM FIFO Interface
    input  logic [127:0] ltsm_msg_fifo,   // LTSM message data 
    input  logic         ltsm_not_empty,  // LTSM FIFO valid (not empty) 
    output logic         ltsm_pop         // Read enable to LTSM FIFO 
);

    // ====================================================================
    // 1. FSM State Definition (SystemVerilog enum)
    // ====================================================================
    // Using enum for state encoding. The compiler will automatically 
    // assign binary values.
    typedef enum logic [1:0] {
        ST_IDLE,       // Wait for data from either FIFO
        ST_READ_LTSM,  // Process LTSM message
        ST_READ_RDI    // Process RDI message
    } state_t;

    state_t current_state, next_state;

    // ====================================================================
    // 2. Sequential Logic: State Register
    // ====================================================================
    // Updates the current state on the rising edge of the clock or 
    // resets asynchronously on the falling edge of reset_n.
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            current_state <= ST_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // ====================================================================
    // 3. Combinational Logic: Next State Logic
    // ====================================================================
    // Implements a Round-Robin scheduling policy to ensure fair access 
    // between LTSM and RDI, preventing starvation.
    always_comb begin
        // Default assignment to prevent accidental latch inference
        next_state = current_state; 

        case (current_state)
            ST_IDLE: begin
                // Priority given to LTSM upon initial wake-up, 
                // otherwise check RDI.
                if (ltsm_not_empty) begin
                    next_state = ST_READ_LTSM;
                end 
                else if (rdi_not_empty) begin
                    next_state = ST_READ_RDI;
                end
            end

            ST_READ_LTSM: begin
                // Wait for the Link Controller to accept the data
                if (LINK_ready) begin 
                    // Round-Robin: Switch to RDI if it has pending data
                    if (rdi_not_empty) begin
                        next_state = ST_READ_RDI; 
                    end
                    // Stay in LTSM if RDI is empty but LTSM has more data
                    else if (ltsm_not_empty) begin
                        next_state = ST_READ_LTSM; 
                    end
                    // Both FIFOs are empty, return to IDLE
                    else begin
                        next_state = ST_IDLE; 
                    end
                end
            end

            ST_READ_RDI: begin
                // Wait for the Link Controller to accept the data
                if (LINK_ready) begin
                    // Round-Robin: Switch to LTSM if it has pending data
                    if (ltsm_not_empty) begin
                        next_state = ST_READ_LTSM; 
                    end
                    // Stay in RDI if LTSM is empty but RDI has more data
                    else if (rdi_not_empty) begin
                        next_state = ST_READ_RDI; 
                    end
                    // Both FIFOs are empty, return to IDLE
                    else begin
                        next_state = ST_IDLE; 
                    end
                end
            end
            
            // Failsafe default state
            default: next_state = ST_IDLE;
        endcase
    end

    // ====================================================================
    // 4. Combinational Logic: Outputs
    // ====================================================================
    // Controls data routing, valid assertion, and FIFO popping based 
    // on the current state and Link Controller readiness.
    always_comb begin
        // 1. Default Values: Crucial for purely combinational logic
        // to avoid unwanted latches.
        LINK_msg       = 128'b0;
        LINK_msg_valid = 1'b0;
        rdi_pop        = 1'b0;
        ltsm_pop       = 1'b0;

        case (current_state)
            ST_IDLE: begin
                // No action needed; defaults apply.
            end

            ST_READ_LTSM: begin
                // Route LTSM data to the Link Controller and assert valid
                LINK_msg       = ltsm_msg_fifo; 
                LINK_msg_valid = 1'b1;          

                // Handshake logic: Only pop the FIFO if the Link Controller
                // is ready to consume the data in this clock cycle.
                if (LINK_ready) begin
                    ltsm_pop = 1'b1;
                end
            end

            ST_READ_RDI: begin
                // Route RDI data to the Link Controller and assert valid
                LINK_msg       = rdi_msg_fifo; 
                LINK_msg_valid = 1'b1;         

                // Handshake logic: Only pop the FIFO if the Link Controller
                // is ready to consume the data in this clock cycle.
                if (LINK_ready) begin
                    rdi_pop = 1'b1;
                end
            end

            default: begin
                // Failsafe: defaults apply.
            end
        endcase
    end

endmodule