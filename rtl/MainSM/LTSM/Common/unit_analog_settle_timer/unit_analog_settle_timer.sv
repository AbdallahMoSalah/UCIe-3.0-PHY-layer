module analog_settle_timer #(
    parameter SETTLE_DELAY = 16
)(
    internal_ltsm_if.timer_analog_settle2state_mp itf
);
    logic [$clog2(SETTLE_DELAY+1)-1:0] counter;

    always_ff @(posedge itf.lclk or negedge itf.rst_n) begin
        if (!itf.rst_n) begin
            counter <= '0;
            itf.analog_settle_time_done <= 1'b0;
        end else begin
            if (itf.analog_settle_timer_en) begin
                if (counter < SETTLE_DELAY) begin
                    counter <= counter + 1;
                    itf.analog_settle_time_done <= 1'b0;
                end else begin
                    itf.analog_settle_time_done <= 1'b1;
                end
            end else begin
                counter <= '0;
                itf.analog_settle_time_done <= 1'b0;
            end
        end
    end
endmodule
