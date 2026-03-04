module VALID_DETECTOR (
    input wire i_clk ,
    input wire i_rst_n ,
    input wire [31:0] RVLD_L ,
    input wire i_Valid_en ,
    input wire [11:0] i_max_error_threshold ,

    output reg O_result_logged_iteration ,
    output reg O_result_logged_consecutive
);

    // =====================================================
    // Parameters
    // =====================================================
    localparam VALID_8B = 8'b11110000;  
    localparam VALID_PATTERN = {VALID_8B, VALID_8B, VALID_8B, VALID_8B};

    localparam MAX_ITERATIONS  = 128;
    localparam MIN_CONSECUTIVE = 16 ;

    localparam IDLE           = 2'b00 ;      
    localparam ITERATIONS_128 = 2'b01 ;
    localparam CONSECUTIVE_16 = 2'b10 ;

    // =====================================================
    // Registers
    // =====================================================
    reg [11:0] error_count ;
    reg [7:0]  consec_count ; 
    reg [5:0]  mismatch_count ;
    reg [7:0]  iteration_counter ;
    
    reg [1:0] current_state; 
    integer i; 

    // =====================================================
    // Mismatch Counter (Combinational)
    // =====================================================
    always @(*) begin
        mismatch_count = 6'd0;   

        if(current_state == ITERATIONS_128) begin
            for (i = 0; i < 32; i = i + 1) begin
                mismatch_count = mismatch_count + 
                                 (RVLD_L[i] ^ VALID_PATTERN[i]);
            end 
        end
    end

    // =====================================================
    // FSM + Main Logic
    // =====================================================
    always @(posedge i_clk or negedge i_rst_n ) begin
        if (!i_rst_n) begin
            current_state               <= IDLE ;
            error_count                 <= 12'd0;
            consec_count                <= 8'd0 ;
            iteration_counter           <= 8'd0;
            O_result_logged_iteration   <= 1'b0 ;
            O_result_logged_consecutive <= 1'b0 ;
        end

        else begin
            case (current_state)

            // =================================================
            // IDLE
            // =================================================
            IDLE: begin
                error_count       <= 0;
                consec_count      <= 0;
                iteration_counter <= 0;

                O_result_logged_iteration   <= 1'b0;
                O_result_logged_consecutive <= 1'b0;

                if (i_Valid_en)
                    current_state <= ITERATIONS_128; // 
            end

            // =================================================
            // ITERATIONS_128 MODE
            // =================================================
            ITERATIONS_128: begin

                iteration_counter <= iteration_counter + 1;
                error_count       <= error_count + mismatch_count;

                if (iteration_counter == MAX_ITERATIONS-1) begin
                    if (error_count > i_max_error_threshold)
                        O_result_logged_iteration <= 1'b1; // FAIL
                    else
                        O_result_logged_iteration <= 1'b0; // PASS

                    current_state <= CONSECUTIVE_16;
                    iteration_counter <= 0;
                    error_count <= 0;
                end
            end

            // =================================================
            // CONSECUTIVE_16 MODE
            // =================================================
            CONSECUTIVE_16: begin

                if (RVLD_L == VALID_PATTERN)
                    consec_count <= consec_count + 4;  // كل cycle فيها 4 بايت
                else
                    consec_count <= 0;

                if (consec_count >= MIN_CONSECUTIVE) begin
                    O_result_logged_consecutive <= 1'b1;  // PASS
                    current_state <= IDLE;
                end
            end

            // =================================================
            default: begin
                current_state <= IDLE;
            end

            endcase
        end
    end

endmodule