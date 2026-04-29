module phase_delay #(parameter real PHASE_DELAY)(
                    input logic in_signal,
                    output logic delayed_signal);

assign #(PHASE_DELAY) delayed_signal  = in_signal;


endmodule


