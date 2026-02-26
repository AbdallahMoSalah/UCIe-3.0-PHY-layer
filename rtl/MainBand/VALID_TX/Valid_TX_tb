`timescale 1ns/1ps

module VALID_TX_tb;

// ============================================================
// Testbench Signals
// ============================================================

reg  i_clk;
reg  i_rst_n;
reg  valid_pattern_en;
reg  valid_frame_en;

wire        O_done;
wire [31:0] o_TVLD_L;

// Expected pattern
localparam VALID_PATTERN_CODE = 32'hF0F0F0F0;

// ============================================================
// DUT Instantiation
// ============================================================

VALID_TX DUT (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .valid_pattern_en(valid_pattern_en),
    .valid_frame_en(valid_frame_en),
    .O_done(O_done),
    .o_TVLD_L(o_TVLD_L)
);

// ============================================================
// Clock Generation (100MHz)
// ============================================================

initial begin
    i_clk = 0;
    forever #5 i_clk = ~i_clk;   // 10ns period
end


// ============================================================
// Test Sequence
// ============================================================

initial begin

    // Initialize
    i_rst_n          = 0;
    valid_pattern_en = 0;
    valid_frame_en   = 0;

    // Apply Reset
    #20;
    i_rst_n = 1;

    $display("------ RESET DONE ------");

    // ========================================================
    // TEST 1 : VALID_PATTERN
    // ========================================================

    @(posedge i_clk);
    valid_pattern_en = 1;

    $display("------ START VALID_PATTERN ------");

    // Wait 35 cycles
    repeat (35) @(posedge i_clk);

    valid_pattern_en = 0;

    @(posedge i_clk);

    // ========================================================
    // TEST 2 : VALID_FRAME
    // ========================================================

    $display("------ START VALID_FRAME ------");

    @(posedge i_clk);
    valid_frame_en = 1;

    repeat (10) @(posedge i_clk);

    valid_frame_en = 0;

    repeat (5) @(posedge i_clk);

    $display("------ TEST FINISHED ------");
    $stop;

end


// ============================================================
// Self Checking Logic
// ============================================================

integer pattern_counter;

always @(posedge i_clk) begin
    if (!i_rst_n) begin
        pattern_counter <= 0;
    end
    else begin

        // ===============================
        // Check VALID_PATTERN behavior
        // ===============================
        if (valid_pattern_en) begin

            if (o_TVLD_L !== VALID_PATTERN_CODE) begin
                $error("ERROR: Pattern output mismatch at time %t", $time);
            end

            pattern_counter <= pattern_counter + 1;

            // O_done must be high only after 32 cycles
            if (pattern_counter < 31 && O_done) begin
                $error("ERROR: O_done asserted too early at %t", $time);
            end

            if (pattern_counter == 31 && !O_done) begin
                $error("ERROR: O_done not asserted at expected cycle %t", $time);
            end
        end
        else begin
            pattern_counter <= 0;
        end


        // ===============================
        // Check VALID_FRAME behavior
        // ===============================
        if (valid_frame_en) begin
            if (o_TVLD_L !== VALID_PATTERN_CODE) begin
                $error("ERROR: VALID_FRAME output mismatch at %t", $time);
            end

            if (O_done) begin
                $error("ERROR: O_done should not assert in VALID_FRAME at %t", $time);
            end
        end

    end
end

endmodule