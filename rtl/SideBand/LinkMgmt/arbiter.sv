// ============================================================================
// Module Name: arbiter
// Description: Round-Robin Arbiter for the Link Management Unit.
//              Arbitrates between LTSM (88-bit) and RDI (9-bit) message FIFOs
//              to feed the Sideband Packetizer. Implements flow control 
//              using the LINK_ready handshake signal.
// ============================================================================

module arbiter (
    // System Signals
    input  logic         clk,
    input  logic         reset_n,

    // Packetizer Interface (Handshake)
    input  logic         LINK_ready,      // Backpressure: Ready signal from Packetizer
    output logic [63:0]  msg_data,        // Message payload (64-bit)
    output logic [15:0]  msg_info,        // Message metadata/info (16-bit)
    output logic [7:0]   msg_n,           // Message number/subcode (8-bit)
    output logic         vld,             // Handshake: Valid signal for outgoing message

    // RDI FIFO Interface (9-bit Status/Request)
    input  logic [8:0]   rdi_msg_fifo,    // RDI message: {stall_bit, msg_no}
    input  logic         rdi_not_empty,   // FIFO Status: Data available
    output logic         rdi_pop,         // Control: Read enable to RDI FIFO 

    // LTSM FIFO Interface (88-bit Link Management)
    input  logic [87:0]  ltsm_msg_fifo,   // LTSM message: {data, info, msg_no}
    input  logic         ltsm_not_empty,  // FIFO Status: Data available
    output logic         ltsm_pop         // Control: Read enable to LTSM FIFO 
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
        msg_data = 64'b0;
        msg_info = 16'b0;
        msg_n    = 8'b0;
        vld      = 1'b0;
        rdi_pop  = 1'b0;
        ltsm_pop = 1'b0;

        case (current_state)
            ST_IDLE: begin
                // No action needed; defaults apply.
            end

            ST_READ_LTSM: begin
                // Extract fields from 88-bit LTSM message:
                // [87:24] -> data, [23:8] -> info, [7:0] -> msg_no
                msg_data = ltsm_msg_fifo[87:24];
                msg_info = ltsm_msg_fifo[23:8];
                msg_n    = ltsm_msg_fifo[7:0];
                vld      = 1'b1;          

                // Handshake logic: Only pop the FIFO if the Link Controller
                // is ready to consume the data in this clock cycle.
                if (LINK_ready) begin
                    ltsm_pop = 1'b1;
                end
            end

            ST_READ_RDI: begin
                // Extract fields from 9-bit RDI message:
                // [8] -> stall flag (mapped to info[0]), [7:0] -> msg_no
                msg_data = 64'b0;
                msg_info = {15'b0, rdi_msg_fifo[8]}; 
                msg_n    = rdi_msg_fifo[7:0];
                vld      = 1'b1;         

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