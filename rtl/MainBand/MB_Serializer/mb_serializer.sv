`timescale 1ns/1ps 

module MB_SERIALIZER #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   mb_clk,
    input  wire                   PLL_clk,
    input  wire                   i_rst_n,
    input  wire                   Ser_en,
    input  wire [DATA_WIDTH-1:0]  in_data,
    output wire                   SER_out
);

// ======================================================
// Internal signals
// ======================================================
reg [7:0]            ser_counter;
reg [DATA_WIDTH-1:0] data_reg;
reg [DATA_WIDTH-1:0] load_reg;

// CDC Synchronizer registers for PLL_clk domain

reg sync3_toggle;

wire rising_ser_en_pll;

// ======================================================
// Latch input data when Ser_en goes high (mb_clk domain)
// ======================================================
reg load_toggle_mb;
// Note: Normally we want in_data to be stable when Ser_en goes high
always @(posedge mb_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        load_reg <= {DATA_WIDTH{1'b0}};
        load_toggle_mb <= 1'b0;
    end else begin
        if (Ser_en) begin
            load_reg  <= in_data;        // Load with mb_clk
            load_toggle_mb <= ~load_toggle_mb; // Signal to start serialization
        end
    end
end
// ======================================================
// CDC: Synchronize Ser_en into PLL_clk domain
// ======================================================
always @(posedge PLL_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        //sync1_toggle <= 1'b0;
        //sync2_toggle <= 1'b0;
        sync3_toggle <= 1'b0;
    end else begin
        //sync1_toggle <= load_toggle_mb;       // 1st sync flop from mb_clk domain
        //sync2_toggle <= sync1_toggle;         // 2nd sync flop
        //sync3_toggle <= sync2_toggle;         // 3rd flop for edge detection
        sync3_toggle <= load_toggle_mb;   
    end
end

// Pulse strictly localized to 1 cycle of PLL_clk on any toggle
assign rising_ser_en_pll = (load_toggle_mb != sync3_toggle);

// ======================================================
// Serializer logic (DDR: Shift 2 bits LSB first)
// ======================================================
wire logic load_condition = (rising_ser_en_pll );


always @(posedge PLL_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        data_reg    <= {DATA_WIDTH{1'b0}};
        ser_counter <= 8'd0;
    end else begin
        if (load_condition) begin
            data_reg    <= {2'b00, load_reg[DATA_WIDTH-1:2]}; // ✅ load direct from in_data and shift
            ser_counter <= 8'd0;          // reset counter
        end else if (ser_counter < (DATA_WIDTH/2)-1) begin
            data_reg    <= {2'b00, data_reg[DATA_WIDTH-1:2]}; // ✅ logical shift right 2 bits
            ser_counter <= ser_counter + 1'b1;
        end else begin
            ser_counter <= 8'd0;
        end
    end
   
end 

// ======================================================
// Serialized output (DDR: MUX pos and neg)
// ======================================================
reg SER_pos_reg;
reg SER_neg_prep;
reg SER_neg_reg;

always @(posedge PLL_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        SER_pos_reg  <= 1'b0;
        SER_neg_prep <= 1'b0;
    end else begin
        if (load_condition) begin
            SER_pos_reg  <= load_reg[0];
            SER_neg_prep <= load_reg[1];
        end else begin
            SER_pos_reg  <= data_reg[0];
            SER_neg_prep <= data_reg[1];
        end
    end
end

always @(negedge PLL_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        SER_neg_reg <= 1'b0;
    end else begin
        SER_neg_reg <= SER_neg_prep;
    end
end

// Select pos register when PLL_clk is High, neg register when PLL_clk is Low
assign SER_out = PLL_clk ? SER_pos_reg : SER_neg_reg;

endmodule
