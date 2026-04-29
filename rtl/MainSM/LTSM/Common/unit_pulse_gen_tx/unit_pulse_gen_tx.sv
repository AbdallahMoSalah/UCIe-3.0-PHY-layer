module unit_pulse_gen_tx #(
    parameter WIDTH = 8
)(
    input  logic lclk,
    input  logic rst_n,
    input  logic pulse_in,
    output logic pulse_out
);
    logic [$clog2(WIDTH)-1:0] counter;
    logic active;

    always_ff @(posedge lclk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= '0;
            active <= 1'b0;
            pulse_out <= 1'b0;
        end else begin
            if (pulse_in && !active) begin
                active <= 1'b1;
                counter <= WIDTH - 1;
                pulse_out <= 1'b1;
            end else if (active) begin
                if (counter > 0) begin
                    counter <= counter - 1;
                    pulse_out <= 1'b1;
                end else begin
                    active <= 1'b0;
                    pulse_out <= 1'b0;
                end
            end else begin
                pulse_out <= 1'b0;
            end
        end
    end
endmodule

