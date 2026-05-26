`timescale 1ns/1ps
/*****   DESERIALIZER FOR VALID LANE  ******/
module MB_DESERIALIZER_VALID #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   MB_clk,
    input  wire                   pll_clk,
    input  wire                   i_rst_n,
    input  wire                   ser_valid_en, 
    input  wire                   ser_data_in,
    output reg                    enable_des_valid_frame,
    output reg  [DATA_WIDTH-1:0]  par_data_out,
    output reg                    de_ser_done
);

/* -------------------------------------------------- */
/* Internal Registers                                 */
/* -------------------------------------------------- */
reg [DATA_WIDTH-1:0] shift_reg;
reg [DATA_WIDTH-1:0] save_data;
reg [5:0]            bit_cnt;

// Handshake registers for CDC (pll_clk -> MB_clk)
reg save_data_toggle;
reg sync1_toggle;
reg sync2_toggle;
reg sync3_toggle;
wire valid_pulse;

/* -------------------------------------------------- */
/* DDR Input Capture (Synthesizable)                 */
/* -------------------------------------------------- */
reg r_data_pos;
reg r_data_neg;
wire r_data_det;

// Capture on rising edge of pll_clk
always @(posedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        r_data_pos <= 1'b0;
    end else if (ser_valid_en) begin
        r_data_pos <= ser_data_in;
    end
end

// Capture on falling edge of pll_clk
always @(negedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        r_data_neg <= 1'b0;
    end else if (ser_valid_en) begin
        r_data_neg <= ser_data_in;
    end
end

// Multiplexer as shown in the Dual Edge Triggered Flip-Flop diagram
assign r_data_det = pll_clk ? r_data_pos : r_data_neg;

// Shifting and counting done on posedge pll_clk (Synthesizable & timing-safe)
always @(posedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        shift_reg        <= {DATA_WIDTH{1'b0}};
        bit_cnt          <= 6'd0;
        save_data        <= {DATA_WIDTH{1'b0}};
        save_data_toggle <= 1'b0;
    end else begin
        if (ser_valid_en) begin
            // Shift in: current ser_data_in (posedge bit) and r_data_neg (negedge bit)
            // LSB first: shift right by 2
            shift_reg <= {ser_data_in, r_data_neg, shift_reg[DATA_WIDTH-1:2]};
            
            if (bit_cnt == (DATA_WIDTH/2) - 1) begin
                bit_cnt          <= 6'd0;
                save_data        <= {ser_data_in, r_data_neg, shift_reg[DATA_WIDTH-1:2]};
                save_data_toggle <= ~save_data_toggle; // Trigger CDC
            end else begin
                bit_cnt <= bit_cnt + 6'd1;
            end
        end else begin
            bit_cnt <= 6'd0;
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

/* -------------------------------------------------- */
/* Enable valid frame logic (MB_clk domain)           */
/* -------------------------------------------------- */
always @(posedge MB_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        enable_des_valid_frame <= 1'b0;
    end else begin
        if (valid_pulse) begin
            enable_des_valid_frame <= (save_data != {DATA_WIDTH{1'b0}});
        end
    end
end

endmodule