module MB_DESERIALIZER (
    input        MB_clk,
    input        pll_clk,
    input        i_ckp,
    input        i_ckn,
    input        i_rst_n,
    input        ser_valid,
    input        ser_data_in,
    output reg [31:0] par_data_out,
    output reg        de_ser_done
);

/* -------------------------------------------------- */
/* Internal Registers                                 */
/* -------------------------------------------------- */
reg [31:0] shift_reg;
reg [31:0] save_data;
reg        save_data_valid;
reg        deassert_save_data_valid;

/* -------------------------------------------------- */
/* Serial to Parallel                                 */
/* -------------------------------------------------- */

always @(posedge i_ckp or posedge i_ckn or negedge i_rst_n) begin
    if (!i_rst_n)
        shift_reg <= 0;
    else
        shift_reg <= {shift_reg[30:0], ser_data_in};
end

/* -------------------------------------------------- */
/* Save data after deserializing                      */
/* -------------------------------------------------- */
always @(posedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        save_data       <= 0;
        save_data_valid <= 0;
    end else begin
        if (ser_valid) begin
            save_data       <= shift_reg;
            save_data_valid <= 1;
        end else if (deassert_save_data_valid) begin
            save_data_valid <= 0;
        end
    end
end

/* -------------------------------------------------- */
/* Sync to MB_clk domain                              */
/* -------------------------------------------------- */
always @(posedge MB_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        par_data_out <= 0;
        de_ser_done  <= 0;
    end else begin
        de_ser_done <= 0; // ✅ default 0 زي الـ reference
        if (save_data_valid) begin
            par_data_out <= save_data;
            de_ser_done  <= 1;
        end
    end
end

/* -------------------------------------------------- */
/* Deassert valid after one cycle                     */
/* -------------------------------------------------- */
always @(posedge de_ser_done) begin
    deassert_save_data_valid = 1;
    @(posedge pll_clk);
    deassert_save_data_valid = 0;
end

endmodule