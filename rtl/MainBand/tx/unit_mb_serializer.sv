`timescale 1ns/1ps 

module unit_mb_serializer #(
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
reg active;

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
        sync3_toggle <= 1'b0;
    end else begin
        sync3_toggle <= load_toggle_mb;       // 3rd flop for edge detection
    end
end

// Pulse strictly localized to 1 cycle of PLL_clk on any toggle
assign rising_ser_en_pll = (sync3_toggle != load_toggle_mb);

// ======================================================
// Serializer logic (DDR: Shift 2 bits LSB first)
// ======================================================
wire logic load_condition = (rising_ser_en_pll);


always @(posedge PLL_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        data_reg    <= {DATA_WIDTH{1'b0}};
        ser_counter <= 8'd0;
        active      <= 1'b0;
    end else begin
        if (load_condition) begin
            data_reg    <= {2'b00, load_reg[DATA_WIDTH-1:2]}; // ✅ load direct from in_data and shift
            ser_counter <= 8'd0;          // reset counter
            active      <= 1'b1;          // start serialization
        end else if (active) begin
            if (ser_counter < (DATA_WIDTH/2)-1) begin
                data_reg    <= {2'b00, data_reg[DATA_WIDTH-1:2]}; // ✅ logical shift right 2 bits
                ser_counter <= ser_counter + 1'b1;
            end else begin
                ser_counter <= 8'd0;
                active      <= 1'b0;      // stop serialization, counter remains at 0 and active remains 0
            end
        end
    end
   
end

// ======================================================
// Serialized output (DDR, glitch-free output mux)
//
// The previous version clocked each phase's output register on the SAME
// edge that the mux selected it (pos reg on posedge -> drives HIGH phase,
// neg reg on negedge -> drives LOW phase). The selecting edge and the
// register update raced, so SER_out briefly showed the stale bit at every
// edge -> the spikes seen on the waveform.
//
// Fix: clock each register on the OPPOSITE edge so it is stable a full
// half-period before the mux selects it. The non-selected register is the
// one changing during any phase, so its update is invisible at the output.
//   - HIGH phase (even bits) <- high_reg, retimed onto the NEGEDGE
//   - LOW  phase (odd  bits) <- low_reg,  retimed onto the POSEDGE
// Both paths carry an equal 1-cycle pipeline latency to keep the stream
// LSB-first. (The first even bit cannot be glitch-free until the negedge
// after load, so one PLL cycle of startup latency is unavoidable.)
// ======================================================
wire even_src = load_condition ? load_reg[0] : data_reg[0]; // bit for HIGH phase
wire odd_src  = load_condition ? load_reg[1] : data_reg[1]; // bit for LOW  phase

reg even_q;     // even bit captured on posedge
reg odd_q;      // odd  bit captured on posedge
reg high_reg;   // drives HIGH phase, retimed onto negedge (stable before rising edge)
reg low_reg;    // drives LOW  phase, retimed onto posedge (stable before falling edge)

always @(posedge PLL_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        even_q  <= 1'b0;
        odd_q   <= 1'b0;
        low_reg <= 1'b0;
    end else begin
        even_q  <= even_src;
        odd_q   <= odd_src;
        low_reg <= odd_q;      // align odd path to the even path's latency
    end
end

always @(negedge PLL_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        high_reg <= 1'b0;
    end else begin
        high_reg <= even_q;    // retime even bit onto the falling edge
    end
end

// Both operands are stable a half-period before they are selected, so the
// mux cannot glitch at the clock edges.
assign SER_out = PLL_clk ? high_reg : low_reg;

endmodule
