`timescale 1ns/1ps

module MB_DESERIALIZER #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   MB_clk,
    input  wire                   pll_clk,
    input  wire                   i_ckp,
    input  wire                   i_ckn,
    input  wire                   i_rst_n,
    input  wire                   ser_valid,
    input  wire                   ser_data_in,
    output reg  [DATA_WIDTH-1:0]  par_data_out,
    output reg                    de_ser_done
);

/* -------------------------------------------------- */
/* Internal Registers                                 */
/* -------------------------------------------------- */
reg [DATA_WIDTH-1:0] shift_reg;
reg [DATA_WIDTH-1:0] save_data;

// Handshake registers for CDC (pll_clk -> MB_clk)
reg save_data_toggle;
reg sync1_toggle;
reg sync2_toggle;
reg sync3_toggle;

/* -------------------------------------------------- */
/* Serial to Parallel (DDR Sampling on pll_clk)       */
/* -------------------------------------------------- */
always @(posedge pll_clk or negedge pll_clk or negedge i_rst_n) begin 
    if (!i_rst_n)
        shift_reg <= {DATA_WIDTH{1'b0}};
    else
        shift_reg <= {ser_data_in, shift_reg[DATA_WIDTH-1:1]}; // LSB first
end

/* -------------------------------------------------- */
/* Save data after deserializing (pll_clk domain)     */
/* -------------------------------------------------- */
always @(posedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        save_data        <= {DATA_WIDTH{1'b0}};
        save_data_toggle <= 1'b0;
    end else begin
        if (ser_valid) begin
            save_data        <= shift_reg;
            save_data_toggle <= ~save_data_toggle; // Flip the toggle to trigger CDC
        end
    end
end

/* -------------------------------------------------- */
/* Sync to MB_clk domain (Toggle Synchronizer)        */
/* -------------------------------------------------- */
always @(posedge MB_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        sync1_toggle <= 1'b0;
        sync2_toggle <= 1'b0;
        sync3_toggle <= 1'b0;
    end else begin
        sync1_toggle <= save_data_toggle;
        sync2_toggle <= sync1_toggle;
        sync3_toggle <= sync2_toggle;
    end
end

assign valid_pulse = (sync2_toggle != sync3_toggle);

/* -------------------------------------------------- */
/* Load Output in MB_clk domain                       */
/* -------------------------------------------------- */
always @(posedge MB_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        par_data_out <= {DATA_WIDTH{1'b0}};
        de_ser_done  <= 1'b0;
    end else begin
        de_ser_done <= 1'b0; // Default off (pulse for 1 cycle)
        if (valid_pulse) begin
            par_data_out <= save_data;
            de_ser_done  <= 1'b1;
        end
    end
end

endmodule