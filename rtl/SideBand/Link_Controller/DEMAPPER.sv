module DEMAPPER (
    input  logic         clk,
    input  logic         rst_n,
    
    // --- Inputs from SerDes ---
    input  logic [63:0]  msg_rcvd,      // Data captured from SerDes
    input  logic         msg_vld_rcvd,  // Valid signal from SerDes

    // --- Outputs to Demux (Router) ---
    output logic [127:0] msg_word_rcvd, // Reconstructed 64-bit or 128-bit message
    output logic         word_vld_rcvd  // Asserts when the full packet is ready
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
            first_half_reg <= 64'b0;
        end else begin
            current_state <= next_state;
            
            // Latch the first half ONLY if we are in IDLE, data is valid, and it's a 128-bit message
            if (current_state == IDLE && msg_vld_rcvd && is_128bit) begin
                first_half_reg <= msg_rcvd;
            end
        end
    end

    // =========================================================
    // 4. FSM Combinational Logic (Next State & Outputs)
    // =========================================================
    always_comb begin
        // 1. Default Values (To prevent unintended latches)
        next_state    = current_state;
        msg_word_rcvd = 128'b0;
        word_vld_rcvd  = 1'b0;

        // 2. State Machine Logic
        case (current_state)
            IDLE: begin
                if (msg_vld_rcvd) begin
                    if (is_128bit) begin
                        // It's a 128-bit message -> Wait for the second half
                        next_state = WAIT_SECOND_HALF;
                    end else begin
                        // It's a 64-bit message -> Output immediately with Zero-Padding
                        msg_word_rcvd = {64'b0, msg_rcvd}; 
                        word_vld_rcvd  = 1'b1; // Raise Valid to Demux
                    end
                end
            end

            WAIT_SECOND_HALF: begin
                // Check if the second half has arrived from SerDes
                if (msg_vld_rcvd) begin
                    // Combine both halves: {Second Half, First Half}
                    msg_word_rcvd = {msg_rcvd, first_half_reg};
                    word_vld_rcvd  = 1'b1; // Raise Valid to Demux
                    
                    next_state = IDLE; // Return to IDLE to process the next packet
                end
            end
        endcase
    end

endmodule