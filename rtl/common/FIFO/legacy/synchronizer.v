module synchronizer #(
    parameter ADDR_WIDTH = 3
) (
    input wire clk,
    input wire rst_n,
    input wire [ADDR_WIDTH:0] sync_in,
    output reg [ADDR_WIDTH:0] sync_reg
);

    reg [ADDR_WIDTH:0] dest_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dest_reg <= 'b0;
            sync_reg <= 'b0;
        end else begin
            dest_reg <= sync_in;
            sync_reg <= dest_reg;
        end
    end
    
endmodule
