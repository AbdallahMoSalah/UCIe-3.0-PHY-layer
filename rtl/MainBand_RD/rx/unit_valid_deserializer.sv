`timescale 1ns/1ps
// =============================================================================
// Module  : unit_valid_deserializer_s3
// Project : UCIe 3.0 Main-Band Physical Layer (RX side)
// Purpose : Solution 3: Posedge-aligned DDR deserializer with 16-cycle counter.
// =============================================================================
module unit_valid_deserializer_s3 #(
    parameter DATA_WIDTH = 32
)(
    input  logic                   pll_clk,
    input  logic                   mb_clk,
    input  logic                   i_rst_n,
    input  logic                   i_en,
    input  logic                   ser_data_in,
    input  logic                   i_valid_pulse,
    input  logic                   i_vcmp_enable,
    input  logic                   i_vcmp_done,

    output logic [DATA_WIDTH-1:0]    o_shift_reg,
    output logic [DATA_WIDTH-1:0]   o_valid_frame_data,
    output logic                    o_valid_frame_vld,
    output logic                      o_count_16       // 0..15 counter
    
);

logic [DATA_WIDTH-1:0] shift_reg;
logic                  r_data_pos;
logic                  prev_ser_data_in;
logic [1:0]            o_state;          // frame-align FSM: 0 = IDLE, 1 = RUNNING
logic [3:0]            o_count;          // 0..15 bit-pair counter (16 pll-cycles = one 32-bit word)


// FIFO signals
logic [DATA_WIDTH-1:0] fifo_rd_data;
logic                  rvalid;
logic                  wfull;
logic                  wready;
logic                  rempty;

// Capture even bit on posedge pll_clk
always @(posedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        r_data_pos <= 1'b0;
    end else if (i_en) begin
        r_data_pos <= ser_data_in;
    end
end

// FSM and Shift register on negedge pll_clk
always @(negedge pll_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        shift_reg        <= {DATA_WIDTH{1'b0}};
        prev_ser_data_in <= 1'b0;
        o_state          <= 1'b0; // IDLE
        o_count          <= 4'd0;
    end else if (!i_en) begin
        shift_reg        <= {DATA_WIDTH{1'b0}};
        prev_ser_data_in <= 1'b0;
        o_state          <= 1'b0;
        o_count          <= 4'd0;
    end else begin
        // Shift register is always free-running
        shift_reg <= {ser_data_in, r_data_pos, shift_reg[DATA_WIDTH-1:2]};
        prev_ser_data_in <= ser_data_in;

        case (o_state)
            2'b00: begin // IDLE
                // Detect rising edge on valid lane (meaning frame is starting)
                if (ser_data_in && !prev_ser_data_in) begin
                    o_state <= 2'b01; // RUNNING
                    o_count <= 4'd0;
                    if (i_vcmp_enable) begin
                        o_state <= 2'b10;
                    end
                end
            end

            2'b01: begin // RUNNING
                if (o_count == 4'd15) begin
                    if (ser_data_in && !prev_ser_data_in) begin
                        o_state <= 2'b01; // Start next frame immediately
                        o_count <= 4'd0;
                    end else begin
                        o_state <= 2'b00; // transition to IDLE
                        o_count <= 4'd0;
                    end
                end else begin
                    o_count <= o_count + 4'd1;
                end
            end
            2'b10: begin // compare
                if (o_count == 4'd15) begin
                    if (~i_vcmp_enable || i_vcmp_done) begin
                        if (ser_data_in && !prev_ser_data_in) begin
                            o_state <= 2'b01; // Start next frame immediately
                            o_count <= 4'd0;
                        end else begin
                            o_state <= 2'b00; // transition to IDLE
                            o_count <= 4'd0;
                        end
                    end else begin
                        o_state <= 2'b10; // compare
                        o_count <= 4'd0;
                    end
                end else begin
                    o_count <= o_count + 4'd1;
                end
            end
        endcase
    end
end

// Asynchronous FIFO instantiation
fifo #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (4),
    .ASYNC      (1)
) u_fifo (
    .W_CLK   (~pll_clk),
    .WRST_N  (i_rst_n),
    .WINC    (i_valid_pulse && i_en),
    .WR_DATA (shift_reg),
    .WFULL   (wfull),
    .WREADY  (wready),
    .R_CLK   (mb_clk),
    .RRST_N  (i_rst_n),
    .RINC    (rvalid),
    .RD_DATA (fifo_rd_data),
    .REMPTY  (rempty),
    .RVALID  (rvalid)
);

// Read controller in mb_clk domain
always @(posedge mb_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_valid_frame_data   <= {DATA_WIDTH{1'b0}};
        o_valid_frame_vld <= 1'b0;
    end else begin
        o_valid_frame_vld <= 1'b0;
        if (i_en && rvalid) begin
            o_valid_frame_data   <= fifo_rd_data;
            o_valid_frame_vld <= 1'b1;
        end
    end
end

// always @(negedge pll_clk) begin
//     if (i_rst_n && o_state) begin
//         $display("[DES_S3] T=%0t r_data_pos=%b prev=%b state=%b count=%d shift_reg=0x%08h",
//                  $time, r_data_pos, prev_ser_data_in, o_state, o_count, shift_reg);
//     end
// end
assign o_count_16 = (o_count == 4'd15);
assign o_shift_reg = shift_reg;

endmodule
