module sb_mapper (

    input  logic         clk,
    input  logic         rst_n,

    // From TX Arbiter
    input  logic [127:0] msg_word_send,
    input  logic         word_vld_send,

    // From SerDes
    input  logic         ser_rdy,

    // Backpressure to Arbiter
    output logic         mapper_rdy,

    // To SerDes
    output logic [63:0]  msg_send,
    output logic         msg_vld_send
);
    import sb_pkg::*;
    // ---------------------------------------------------------
    // Internal Registers
    // ---------------------------------------------------------

    logic [63:0] second_half_reg;

    typedef enum logic [1:0] {
        IDLE,
        SEND_SECOND_HALF
    } state_t;

    state_t current_state, next_state;

    // ---------------------------------------------------------
    // Opcode Decode
    // ---------------------------------------------------------

    sb_opcode_e opcode;
    logic       is_128bit;

    assign opcode = sb_opcode_e'(msg_word_send[4:0]);

    // ---------------------------------------------------------
    // Determine Message Length
    // ---------------------------------------------------------

    always_comb begin

        case (opcode)

            SB_32_MEM_WRITE,
            SB_32_DMS_REG_WRITE,
            SB_32_CFG_WRITE,
            SB_64_MEM_WRITE,
            SB_64_DMS_REG_WRITE,
            SB_64_CFG_WRITE,
            SB_COMPLETION_WITH_32_DATA,
            SB_COMPLETION_WITH_64_DATA,
            SB_MSG_WITH_64_DATA,
            SB_MNGT_PORT_MSG_WITH_DATA:
                is_128bit = 1'b1;

            default:
                is_128bit = 1'b0;

        endcase

    end

    // ---------------------------------------------------------
    // Handshake Fire Signals
    // ---------------------------------------------------------

    logic arb_fire;

    assign arb_fire = word_vld_send && mapper_rdy;

    // ---------------------------------------------------------
    // FSM State Register
    // ---------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin
            current_state   <= IDLE;
            second_half_reg <= '0;
        end
        else begin

            current_state <= next_state;

            // latch second half
            if (arb_fire && is_128bit) begin
                second_half_reg <= msg_word_send[127:64];
            end

        end

    end

    // ---------------------------------------------------------
    // FSM Next State Logic
    // ---------------------------------------------------------

    always_comb begin

        next_state = current_state;

        case (current_state)


            IDLE: begin
                if (arb_fire && is_128bit)
                    next_state = SEND_SECOND_HALF;
            end

            SEND_SECOND_HALF: begin
                if (ser_rdy)
                    next_state = IDLE;
            end

            default:
                next_state = IDLE;

        endcase

    end

    // ---------------------------------------------------------
    // Output Logic
    // ---------------------------------------------------------

    always_comb begin

        // defaults
        
        msg_vld_send    = 1'b0;
        msg_send        = '0;
        mapper_rdy    = 1'b0;

        case (current_state)

            //--------------------------------
            // IDLE
            //--------------------------------
            IDLE: begin

                mapper_rdy = ser_rdy;

                if (word_vld_send) begin
                    msg_send  = msg_word_send[63:0];
                    msg_vld_send = 1'b1;
                end

            end

            //--------------------------------
            // SEND_SECOND_HALF
            //--------------------------------
            SEND_SECOND_HALF: begin

                msg_send  = second_half_reg;
                msg_vld_send = 1'b1;

            end

            default: begin
                mapper_rdy = 1'b0;
                msg_send = '0;
                msg_vld_send = 1'b0;
            end

        endcase

    end

endmodule
