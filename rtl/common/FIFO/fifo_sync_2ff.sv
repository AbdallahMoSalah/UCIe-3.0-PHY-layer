// =============================================================================
// Module      : fifo_sync_2ff
// Description : 2-flop synchronizer for crossing clock domains.
//               Used ONLY in ASYNC mode to pass Gray-coded pointers.
// =============================================================================
module fifo_sync_2ff #(
    parameter int ADDR_WIDTH = 4
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic [ADDR_WIDTH:0]   sync_in,
    output logic [ADDR_WIDTH:0]   sync_out
);

    logic [ADDR_WIDTH:0] meta_reg;  // metastability catching FF

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta_reg <= '0;
            sync_out <= '0;
        end else begin
            meta_reg <= sync_in;
            sync_out <= meta_reg;
        end
    end

endmodule
