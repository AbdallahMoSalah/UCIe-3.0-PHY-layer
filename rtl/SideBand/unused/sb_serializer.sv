module sb_serializer #(
    parameter DATA_WIDTH = 64,
    parameter GAP_WIDTH  = 32
) (
    input logic clk,
    input logic rst_n,

    // control
    input logic pmo_en,

    // Parallel interface
    input  logic [DATA_WIDTH-1:0] tx_parallel_data,
    input  logic                  tx_data_valid,
    output logic                  tx_ready,

    // Serial output
    output logic tx_serial_out,

    // Forwarded sideband clock
    output logic TXCKSB
);

  ////////////////////////////////////////////////////////////
  // State Machine
  ////////////////////////////////////////////////////////////

  typedef enum logic [1:0] {
    IDLE,
    SHIFT,
    GAP
  } state_t;

  state_t state, next_state;
  ////////////////////////////////////////////////////////////
  // Registers
  ////////////////////////////////////////////////////////////

  logic [DATA_WIDTH-1:0] shift_reg;
  logic [$clog2(DATA_WIDTH):0] bit_cnt;
  logic gated_en;

  ////////////////////////////////////////////////////////////
  // State Register
  ////////////////////////////////////////////////////////////

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= IDLE;
    else begin
      state <= next_state;
    end
  end

  ////////////////////////////////////////////////////////////
  // Next State Logic
  ////////////////////////////////////////////////////////////

  always_comb begin

    next_state = state;

    case (state)

      IDLE: if (tx_data_valid) next_state = SHIFT;

      SHIFT:
      if (bit_cnt == DATA_WIDTH - 1) begin
        if (pmo_en) begin  // PMO mode
          if (tx_data_valid) begin
            next_state = SHIFT;
          end else begin
            next_state = IDLE;
          end
        end else begin
          next_state = GAP;
        end

      end

      GAP:
      if (bit_cnt == GAP_WIDTH - 1) begin
        if (tx_data_valid) next_state = SHIFT;
        else next_state = IDLE;
      end

    endcase

  end

  ////////////////////////////////////////////////////////////
  // Counter
  ////////////////////////////////////////////////////////////

  always_ff @(posedge clk or negedge rst_n) begin

    if (!rst_n) bit_cnt <= '0;

    else if (state == SHIFT) begin

      if (bit_cnt == DATA_WIDTH - 1) bit_cnt <= '0;
      else bit_cnt <= bit_cnt + 1'b1;

    end else if (state == GAP) begin

      if (bit_cnt == GAP_WIDTH - 1) bit_cnt <= '0;
      else bit_cnt <= bit_cnt + 1'b1;

    end else bit_cnt <= '0;

  end

  ////////////////////////////////////////////////////////////
  // Shift Register
  ////////////////////////////////////////////////////////////

  always_ff @(posedge clk or negedge rst_n) begin

    if (!rst_n) shift_reg <= '0;

    else begin

      // load new packet
      if (tx_ready && tx_data_valid) shift_reg <= tx_parallel_data;
      // normal shifting
      else if (state == SHIFT) shift_reg <= {1'b0, shift_reg[DATA_WIDTH-1:1]};

    end

  end

  ////////////////////////////////////////////////////////////
  // Serial Output
  ////////////////////////////////////////////////////////////

  always_comb begin
    if (state == SHIFT) tx_serial_out = shift_reg[0];
    else tx_serial_out = 1'b0;
  end

  ////////////////////////////////////////////////////////////
  // Ready Signal
  ////////////////////////////////////////////////////////////

  always_comb begin

    tx_ready = 0;

    case (state)

      IDLE: tx_ready = 1;

      SHIFT: if (bit_cnt == DATA_WIDTH - 1 && pmo_en) tx_ready = 1;  // allows PMO

      GAP: if (bit_cnt == GAP_WIDTH - 1) tx_ready = 1;

    endcase

  end

  ////////////////////////////////////////////////////////////
  // Forwarded Clock
  ////////////////////////////////////////////////////////////
assign gated_en = (next_state == SHIFT);

CLK_GATE forward_clock(
.CLK_EN(gated_en),
.CLK(clk),
.GATED_CLK(TXCKSB)
);


/*   always_comb begin
    if (state == SHIFT) TXCKSB = clk;
    else TXCKSB = 1'b0;
  end
 */
endmodule