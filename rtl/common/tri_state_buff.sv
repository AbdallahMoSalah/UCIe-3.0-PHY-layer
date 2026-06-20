module tri_state_buff (
    input  logic data_in,
    input  logic [1:0] en,
    output logic data_out
);
    assign data_out = en[1] ? 1'bz : en[0] ? data_in : 1'b0;
endmodule