module VALID_DETECTOR (
    input  wire        i_clk,                    // Clock
    input  wire        i_rst_n,                  // Active-low reset
    input  wire [31:0] RVLD_L,                  // Received valid data
    input  wire        i_Valid_en,              // Start detection
    input  wire [11:0] i_max_error_threshold,   // Max allowed bit errors

    output reg         O_result_logged_iteration,   // Iteration check result
    output reg         O_result_logged_consecutive  // 16 consecutive 8-bit iterations result
);

    // =====================================================
    // Parameters
    // =====================================================
    localparam VALID_8B       = 8'b11110000;                     // Single iteration pattern
    localparam VALID_PATTERN  = {VALID_8B, VALID_8B, VALID_8B, VALID_8B}; // 32-bit pattern
    localparam MAX_ITERATIONS  = 128;                             // Number of iterations for bit check
    localparam MIN_CONSECUTIVE = 16;                              // Minimum consecutive correct iterations

    localparam IDLE           = 2'b00;
    localparam ITERATIONS_128 = 2'b01;
    localparam CONSECUTIVE_16 = 2'b10;

    // =====================================================
    // Registers
    // =====================================================
    reg [11:0] error_count;            // Count of bit mismatches
    reg [7:0]  iteration_counter;      // Iteration index for 128-cycle check
    reg [7:0]  consec_count;           // Count of consecutive correct 8-bit iterations
    reg [1:0]  current_state;          // FSM state
    reg [5:0]  mismatch_count;         // Mismatches in current 32-bit word
    reg [2:0]  valid_bytes;            // Number of correct 8-bit iterations in current 32-bit word

    integer i;

    // =====================================================
    // Split 32-bit received word into 4 bytes
    // =====================================================
    wire [7:0] seg_0 = RVLD_L[7:0];
    wire [7:0] seg_1 = RVLD_L[15:8];
    wire [7:0] seg_2 = RVLD_L[23:16];
    wire [7:0] seg_3 = RVLD_L[31:24];

    // =====================================================
    // Bit Mismatch Counter (for 128 iterations mode)
    // =====================================================
    always @(*) begin
        mismatch_count = 0;
        for (i = 0; i < 32; i = i + 1) begin
            mismatch_count = mismatch_count + (RVLD_L[i] ^ VALID_PATTERN[i]);
        end
    end

    // =====================================================
    // Count valid bytes per 32-bit word (for consecutive mode)
    // =====================================================
    always @(*) begin
        valid_bytes = 0;

        if (seg_0 == VALID_8B) valid_bytes = valid_bytes + 1;
        if (seg_1 == VALID_8B) valid_bytes = valid_bytes + 1;
        if (seg_2 == VALID_8B) valid_bytes = valid_bytes + 1;
        if (seg_3 == VALID_8B) valid_bytes = valid_bytes + 1;
    end

    // =====================================================
    // FSM
    // =====================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            // Reset all counters and flags
            current_state               <= IDLE;
            error_count                 <= 0;
            iteration_counter           <= 0;
            consec_count                <= 0;
            O_result_logged_iteration   <= 0;
            O_result_logged_consecutive <= 0;
        end
        else begin
            case (current_state)

            // =============================================
            // IDLE: Wait for i_Valid_en
            // =============================================
            IDLE: begin
                error_count                 <= 0;
                iteration_counter           <= 0;
                consec_count                <= 0;
                O_result_logged_iteration   <= 0;
                O_result_logged_consecutive <= 0;

                if (i_Valid_en)
                    current_state <= ITERATIONS_128;
            end

            // =============================================
            // ITERATIONS_128: Count bit mismatches for 128 iterations
            // =============================================
            ITERATIONS_128: begin
                iteration_counter <= iteration_counter + 1;
                error_count       <= error_count + mismatch_count;

                if (iteration_counter == MAX_ITERATIONS-1) begin
                    // Set iteration result: 1 = FAIL, 0 = PASS
                    if ((error_count + mismatch_count) > i_max_error_threshold)
                        O_result_logged_iteration <= 1'b1;   // FAIL
                    else
                        O_result_logged_iteration <= 1'b0;   // PASS

                    iteration_counter <= 0;
                    error_count       <= 0;
                    current_state     <= CONSECUTIVE_16;
                end
            end

            // =============================================
            // CONSECUTIVE_16: Check for 16 consecutive 8-bit correct iterations
            // =============================================
            CONSECUTIVE_16: begin
                // Update consecutive counter based on valid bytes
                if (valid_bytes == 4)
                    consec_count <= consec_count + 4;
                else if (valid_bytes == 0)
                    consec_count <= 0;
                else
                    consec_count <= valid_bytes; // restart sequence on partial correctness

                // Check if we reached 16 consecutive iterations
                if (consec_count >= MIN_CONSECUTIVE) begin
                    O_result_logged_consecutive <= 1'b1;
                    current_state <= IDLE;
                end
            end

            // =============================================
            // Default: go to IDLE
            // =============================================
            default: current_state <= IDLE;

            endcase
        end
    end

endmodule