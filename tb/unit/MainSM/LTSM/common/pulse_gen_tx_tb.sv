`timescale 1ns/1ps

module pulse_gen_tx_tb;
    logic lclk;
    logic rst_n;
    logic pulse_in;
    logic pulse_out;

    localparam WIDTH = 8;
    localparam CLK_PERIOD = 10;

    pulse_gen_tx #(
        .WIDTH(WIDTH)
    ) dut (
        .lclk(lclk),
        .rst_n(rst_n),
        .pulse_in(pulse_in),
        .pulse_out(pulse_out)
    );

    // Clock generation
    always #(CLK_PERIOD/2) lclk = ~lclk;

    int error_count = 0;

    task check_errors;
        if (error_count > 0) begin
            $display("FAILED: %0d errors found in pulse_gen_tx_tb", error_count);
            $stop;
        end else begin
            $display("PASSED: pulse_gen_tx_tb completed successfully.");
        end
    endtask

    initial begin
        lclk = 0;
        rst_n = 0;
        pulse_in = 0;

        #25;
        rst_n = 1;
        @(posedge lclk);

        // Test 1: Single cycle pulse_in
        $display("Test 1: Single cycle pulse_in");
        @(posedge lclk);
        pulse_in <= 1;
        @(posedge lclk);
        pulse_in <= 0;
        
        // Pulse should be high for exactly WIDTH cycles starting from the next clock edge
        for (int i = 0; i < WIDTH; i++) begin
            @(posedge lclk);
            #1;
            if (pulse_out !== 1'b1) begin
                $display("ERROR @%0t: pulse_out should be high at cycle %0d", $time, i);
                error_count++;
            end
        end
        @(posedge lclk);
        #1;
        if (pulse_out !== 1'b0) begin
            $display("ERROR @%0t: pulse_out should be low after %0d cycles", $time, WIDTH);
            error_count++;
        end

        #50;

        // Test 2: Multiple cycle pulse_in
        $display("Test 2: Multiple cycle pulse_in");
        @(posedge lclk);
        pulse_in <= 1;
        repeat(3) @(posedge lclk);
        pulse_in <= 0;
        
        // The first sample happened at the first posedge after pulse_in went high.
        // So pulse_out should have started high 1 cycle after that first posedge.
        // Wait, my manual trace:
        // Posedge 1: pulse_in=1 sampled. active->1, pulse_out->1 (at Posedge 2)
        // So from Posedge 2 to Posedge 9 inclusive, pulse_out=1.
        
        // We are currently at Posedge 4 (after repeat(3)).
        // Pulse was 1 at P2, P3, P4.
        // We need to check P5, P6, P7, P8, P9.
        
        // Actually, let's just use a fork or a more general checker.
        // Or simpler: just restart the test and check from the beginning of the pulse.
        
        #50;
        $display("Test 2 (re-run): Multiple cycle pulse_in");
        @(posedge lclk);
        pulse_in <= 1;
        fork
            begin
                repeat(3) @(posedge lclk);
                pulse_in <= 0;
            end
            begin
                for (int i = 0; i < WIDTH; i++) begin
                    @(posedge lclk);
                    #1;
                    if (pulse_out !== 1'b1) begin
                        $display("ERROR @%0t: pulse_out should be high at cycle %0d", $time, i);
                        error_count++;
                    end
                end
                @(posedge lclk);
                #1;
                if (pulse_out !== 1'b0) begin
                    $display("ERROR @%0t: pulse_out should be low after %0d cycles", $time, WIDTH);
                    error_count++;
                end
            end
        join

        #100;
        check_errors;
        $finish;
    end

endmodule
