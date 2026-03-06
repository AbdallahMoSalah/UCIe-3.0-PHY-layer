`timescale 1ns/1ps

module MB_SERIALIZER_TB;

// =====================================================
// Parameters
// =====================================================
parameter DATA_WIDTH = 32;
parameter CLK_PERIOD = 10; // 100 MHz

// =====================================================
// DUT Signals
// =====================================================
reg                   i_clk;
reg                   i_rst_n;
reg                   Ser_en;
reg  [DATA_WIDTH-1:0] in_data;
wire                  SER_out;

// =====================================================
// DUT Instantiation
// =====================================================
MB_SERIALIZER #(.DATA_WIDTH(DATA_WIDTH)) DUT (
    .i_clk   (i_clk),
    .i_rst_n (i_rst_n),
    .Ser_en  (Ser_en),
    .in_data (in_data),
    .SER_out (SER_out)
);

// =====================================================
// Clock Generation
// =====================================================
initial i_clk = 0;
always #(CLK_PERIOD/2) i_clk = ~i_clk;

// =====================================================
// Tasks
// =====================================================

// Reset Task
task apply_reset;
    begin
        i_rst_n = 0;
        Ser_en  = 0;
        in_data = 0;
        repeat(4) @(posedge i_clk);
        @(negedge i_clk);
        i_rst_n = 1;
    end
endtask

// Serialize Task + Check
task serialize_and_check;
    input [DATA_WIDTH-1:0] data;
    integer bit_idx;
    reg [DATA_WIDTH-1:0] captured;
    begin
        in_data = data;
        Ser_en  = 1;

        // انتظر cycle أول عشان الداتا تتحمل
        @(posedge i_clk); #1;

        // دلوقتي سمبل
        for (bit_idx = 0; bit_idx < DATA_WIDTH; bit_idx = bit_idx + 1) begin
            captured[bit_idx] = SER_out;
            @(posedge i_clk); #1;
        end

        Ser_en = 0;
        @(posedge i_clk);

        if (captured === data)
            $display("PASS | data = 0x%08h", data);
        else
            $display("FAIL | data = 0x%08h | captured = 0x%08h", data, captured);
    end
endtask
// =====================================================
// Test Scenarios
// =====================================================
initial begin
    $dumpfile("MB_SERIALIZER_TB.vcd");
    $dumpvars(0, MB_SERIALIZER_TB);

    // 1) Reset
    apply_reset;

    // 2) Normal word
    serialize_and_check(32'hDEAD_BEEF);

    // 3) All zeros
    serialize_and_check(32'h0000_0000);

    // 4) All ones
    serialize_and_check(32'hFFFF_FFFF);

    // 5) Alternating bits
    serialize_and_check(32'hAAAA_AAAA);

    // 6) Mid-transfer reset
    in_data = 32'h1234_5678;
    Ser_en  = 1;
    repeat(10) @(posedge i_clk);
    i_rst_n = 0;
    repeat(2) @(posedge i_clk);
    i_rst_n = 1;
    Ser_en  = 0;
    $display("Mid-transfer reset applied");

    // 7) SER_EN deassert then reassert
    serialize_and_check(32'hCAFE_BABE);
    repeat(5) @(posedge i_clk); // gap
    serialize_and_check(32'h1234_5678);

    $display("All tests done!");
    $finish;
end

endmodule