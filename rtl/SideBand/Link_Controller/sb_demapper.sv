module sb_demapper (
    input  logic         clk,
    input  logic         rst_n,
    
    // --- Inputs from SerDes ---
    input  logic [63:0]  msg_rcvd,      // Data captured from SerDes
    input  logic         msg_vld_rcvd,     // Valid signal from SerDes

    // --- Outputs to Demux (Router) ---
    output logic [127:0] msg_word_rcvd, // Reconstructed 64-bit or 128-bit message
    output logic         word_vld_rcvd  // Asserts when the full packet is rdy
);

    // =========================================================
    // 1. Internal Signals & FSM States
    // =========================================================
    logic [4:0]  opcode;
    logic        is_128bit;
    logic [63:0] first_half_reg; 

    // Extracting the 5-bit opcode from the incoming message
    assign opcode = msg_rcvd[4:0];

    typedef enum logic {
        IDLE,               // Waiting for new message
        WAIT_SECOND_HALF    // Waiting for the upper 64-bits
    } state_t;

    state_t current_state, next_state;

    // =========================================================
    // 2. Opcode Decoder (Combinational Logic)
    // =========================================================
    always_comb begin
        is_128bit = 1'b0; // Default: message is 64-bit
        
        // Check if the opcode belongs to the 128-bit family
        case (opcode)
            5'b00001, 5'b00011, 5'b00101, 5'b01001, 5'b01011, 
            5'b01101, 5'b10001, 5'b11001, 5'b11000, 5'b11011: begin
                is_128bit = 1'b1;
            end
                
            default: begin
                is_128bit = 1'b0;
            end
        endcase
    end

    // =========================================================
    // 3. FSM Sequential Logic (State Update & Data Buffering)
    // =========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state  <= IDLE;
        end else begin
            current_state <= next_state;
            end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            first_half_reg <= 64'b0;
            msg_word_rcvd <= 128'b0;
            word_vld_rcvd <= 1'b0;
        end else begin
            if (msg_vld_rcvd && current_state == IDLE && is_128bit) begin
                first_half_reg <= msg_rcvd;
            end
            if (msg_vld_rcvd && current_state == IDLE && !is_128bit) begin
                msg_word_rcvd <= {64'b0, msg_rcvd}; // Pad upper 64-bits with zeros
                word_vld_rcvd <= 1'b1; // Full 64-bit message is rdy
            end else if (msg_vld_rcvd && current_state == WAIT_SECOND_HALF) begin
                msg_word_rcvd <= {msg_rcvd, first_half_reg}; // Combine halves
                word_vld_rcvd <= 1'b1; // Full 128-bit message is rdy
            end else begin
                word_vld_rcvd <= 1'b0; // Default: not valid
            end
        end
    end

    always_comb begin
        next_state = current_state; // Default: stay in current state
        case (current_state)
            IDLE: begin
                if (msg_vld_rcvd && is_128bit) begin
                    next_state = WAIT_SECOND_HALF; // Wait for the second half
                end else if (msg_vld_rcvd && !is_128bit) begin
                    next_state = IDLE; // Stay in IDLE, 64-bit message is rdy immediately
                end
            end

            WAIT_SECOND_HALF: begin
                if (msg_vld_rcvd) begin
                    next_state = IDLE; // After receiving second half, go back to IDLE
                end
            end

            default: next_state = IDLE;
        endcase
/*
        // DEBUG
        // synthesis translate_off
        if (msg_vld_rcvd) begin
            $display("[%0t] [sb_demapper] msg_vld_rcvd=1 opcode=%b is_128bit=%b current_state=%0d msg_rcvd=%h",
                     $time, opcode, is_128bit, current_state, msg_rcvd);
        end
        if (word_vld_rcvd) begin
            $display("[%0t] [sb_demapper] Outputting word_vld_rcvd=1 msg_word_rcvd[127:64]=%h [63:0]=%h",
                     $time, msg_word_rcvd[127:64], msg_word_rcvd[63:0]);
        end
        // synthesis translate_on
*/
    end

endmodule