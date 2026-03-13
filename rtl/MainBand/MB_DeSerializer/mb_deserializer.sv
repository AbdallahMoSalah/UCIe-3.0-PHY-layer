module MB_DESERIALIZER (
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire        in_des_data,
    output reg [31:0]  deser_data_out
);

reg [5:0]  des_counter;
reg [31:0] deser_data_out_temp;

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        des_counter         <= 0;
        deser_data_out_temp <= 0;
        deser_data_out      <= 0;
    end else begin
       deser_data_out_temp <= {in_des_data, deser_data_out_temp[31:1]};
        des_counter         <= des_counter + 1;

        if (des_counter == 6'd31) begin
         deser_data_out <= {in_des_data, deser_data_out_temp[31:1]};
            des_counter    <= 0;
        end
    end
end

endmodule