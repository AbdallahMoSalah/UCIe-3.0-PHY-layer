module VALID_DETECTOR (
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire [31:0] RVLD_L,
    input  wire [11:0] i_max_error_threshold,
    input  wire        i_enable_cons,
    input  wire        i_enable_128,
    input  wire        i_enable_detector,

    output reg         detection_result,
    output reg         o_valid_frame_detect
);

    // =====================================================
    // Parameters
    // =====================================================
    localparam VALID_8B      = 8'b11110000;
    localparam VALID_PATTERN = {VALID_8B, VALID_8B, VALID_8B, VALID_8B};

    localparam MAX_ITERATIONS  = 128;
    localparam MIN_CONSECUTIVE = 16;

    localparam IDLE      = 2'b00;
    localparam ITER_128  = 2'b01;
    localparam CONSEC_16 = 2'b10;

    // =====================================================
    // Registers
    // =====================================================
    reg [7:0]  consec_count;
    reg [11:0] error_count;
    reg [5:0]  mismatch_count;
    reg [2:0]  valid_bytes;
    reg [7:0]  iteration_counter;

    integer i;

    // =====================================================
    // Mode Selection & Frame Detect
    // =====================================================
    wire [1:0] mode_select = {i_enable_cons, i_enable_128};

    wire valid_frame_detect = (RVLD_L != VALID_PATTERN && i_enable_detector) ? 1'b1 : 1'b0;

    always @(posedge i_clk or negedge i_rst_n) begin : proc_o_valid_frame_detect
        if (~i_rst_n) begin
            o_valid_frame_detect <= 0;
        end else if (i_enable_detector) begin
            o_valid_frame_detect <= valid_frame_detect;
        end
    end

    // =====================================================
    // Split 32-bit word into 4 bytes
    // =====================================================
    wire [7:0] seg_0 = RVLD_L[7:0];
    wire [7:0] seg_1 = RVLD_L[15:8];
    wire [7:0] seg_2 = RVLD_L[23:16];
    wire [7:0] seg_3 = RVLD_L[31:24];

    // =====================================================
    // Valid Bytes Counter (Combinational)
    // =====================================================
    always @(*) begin
        valid_bytes = 0;
        if (seg_0 == VALID_8B) valid_bytes = valid_bytes + 1;
        if (seg_1 == VALID_8B) valid_bytes = valid_bytes + 1;
        if (seg_2 == VALID_8B) valid_bytes = valid_bytes + 1;
        if (seg_3 == VALID_8B) valid_bytes = valid_bytes + 1;
    end

    // =====================================================
    // Bit Mismatch Counter (Combinational)
    // =====================================================
    always @(*) begin
        if (mode_select == ITER_128) begin
            mismatch_count = 6'b0;
            for (i = 0; i < 32; i = i + 1) begin
                mismatch_count = mismatch_count + (RVLD_L[i] ^ VALID_PATTERN[i]);
            end
        end else begin
            mismatch_count = 6'b0;
        end
    end

    // =====================================================
    // Sequential Logic
    // =====================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            consec_count      <= 8'b0;
            error_count       <= 12'b0;
            iteration_counter <= 8'b0;
            detection_result  <= 1'b1;
        end 
        else if (i_enable_detector) begin
            case (mode_select)
                ITER_128: begin
                    iteration_counter <= iteration_counter + 1;
                    error_count       <= error_count + mismatch_count;

                    if (error_count > i_max_error_threshold) begin
                        detection_result <= 1'b0;
                    end else begin
                        detection_result <= 1'b1;
                    end

                    if (iteration_counter == MAX_ITERATIONS - 1) begin
                        iteration_counter <= 0;
                        error_count       <= 0;
                    end
                end
                
                CONSEC_16: begin
                    if (valid_bytes == 4)
                        consec_count <= consec_count + 4;
                    else if (valid_bytes == 0)
                        consec_count <= 0;
                    else
                        consec_count <= valid_bytes;

                    if (consec_count >= MIN_CONSECUTIVE) begin
                        detection_result <= 1'b1;
                    end else begin
                        detection_result <= 1'b0;
                    end
                end
                
                IDLE: begin
                    consec_count      <= 8'b0;
                    error_count       <= 12'b0;
                    iteration_counter <= 8'b0;
                    detection_result  <= 1'b1;
                end
                
                default: begin
                    consec_count      <= 8'b0;
                    error_count       <= 12'b0;
                    iteration_counter <= 8'b0;
                    detection_result  <= 1'b1;
                end
            endcase
        end
    end

endmodule