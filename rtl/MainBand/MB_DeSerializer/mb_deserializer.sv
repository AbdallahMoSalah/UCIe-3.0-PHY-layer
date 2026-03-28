module MB_DESERIALIZER (
    input  wire        mb_clk,
    input  wire         i_clkp,
    input  wire         i_clkn,
    input  wire        PLL_clk,
    input  wire        i_rst_n,
    input  wire        deser_en,
    input  wire        in_des_data,
    output reg [31:0]  deser_data_out ,
    output reg         deser_done 
);

reg [5:0]  des_counter;
reg [31:0] deser_data_out_reg;
reg [31:0] data_save_reg;
reg        deser_en_reg;
reg        data_valid_reg;

always @(posedge i_clkp or posedge i_clkn or negedge i_rst_n) begin
    if(!i_rst_n) begin
        deser_data_out_reg <= 0;
end
else begin
        deser_data_out_reg <= {deser_data_out_reg[30:0], in_des_data};
    end
end


always @(posedge PLL_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        
    end
end


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