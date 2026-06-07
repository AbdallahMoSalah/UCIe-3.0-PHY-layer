module Mapper #(
    parameter WIDTH      = 32,
    parameter NUM_LANES  = 16,
    parameter N_BYTES    = 64
)(
    input  wire                      i_clk,
    input  wire                      i_rst_n,
    input  wire [8*N_BYTES-1:0]      i_in_data,
    input  wire                      mapper_en,
    input  wire [2:0]                i_width_deg_map,
    input  wire                      lp_irdy,
    input  wire                      lp_valid,

    output reg  [WIDTH-1:0] o_lane_0,  o_lane_1,  o_lane_2,  o_lane_3,
    output reg  [WIDTH-1:0] o_lane_4,  o_lane_5,  o_lane_6,  o_lane_7,
    output reg  [WIDTH-1:0] o_lane_8,  o_lane_9,  o_lane_10, o_lane_11,
    output reg  [WIDTH-1:0] o_lane_12, o_lane_13, o_lane_14, o_lane_15,
    output reg              out_scramble_en,
    output reg              mapper_ready // pl_trdy
);

    //============================================================
    // Degrade Modes
    //============================================================
    localparam NONE_DEGRADE           = 3'b000;
    localparam DEGRADE_LANES_0_TO_7   = 3'b001;
    localparam DEGRADE_LANES_8_TO_15  = 3'b010;
    localparam DEGRADE_LANES_0_TO_15  = 3'b011;
    localparam DEGRADE_LANES_0_TO_3   = 3'b100;
    localparam DEGRADE_LANES_4_TO_7   = 3'b101;

    //============================================================
    // Calculations
    //============================================================
    localparam N_BYTE_PER_LANE = WIDTH / 8;                    // 4
    localparam N_BYTES_VAL     = 64;
    localparam NUM_WORDS       = N_BYTES_VAL / N_BYTE_PER_LANE; // 16

    localparam CLOCK_CYCLES_16 = NUM_WORDS / 16;  // 1
    localparam CLOCK_CYCLES_8  = NUM_WORDS / 8;   // 2
    localparam CLOCK_CYCLES_4  = NUM_WORDS / 4;   // 4

    //============================================================
    // Internal Registers and Handshake Logic
    //============================================================
    reg [1:0] cycle_count;

    // Latched registers for stabilizing mapping data mid-transfer
    reg [8*N_BYTES-1:0] reg_in_data;
    reg [2:0]           reg_width_deg_map;

    // Active (lp_irdy && lp_valid): adapter has valid data and wants PL to sample
    wire data_active = lp_irdy && lp_valid;

    // Helper for active degradation mode
    wire mode_active = (i_width_deg_map == DEGRADE_LANES_0_TO_7)  ||
                       (i_width_deg_map == DEGRADE_LANES_8_TO_15) ||
                       (i_width_deg_map == DEGRADE_LANES_0_TO_15) ||
                       (i_width_deg_map == DEGRADE_LANES_0_TO_3)  ||
                       (i_width_deg_map == DEGRADE_LANES_4_TO_7);

    // Handshake and active signals
    wire handshake = lp_valid && lp_irdy && mapper_ready && mapper_en && mode_active;
    wire is_active = handshake || (cycle_count != 2'd0);

    // Multiplex between live input on handshake cycle and latched input on subsequent cycles
    wire [8*N_BYTES-1:0] active_data          = (cycle_count == 2'd0) ? i_in_data       : reg_in_data;
    wire [2:0]           active_width_deg_map = (cycle_count == 2'd0) ? i_width_deg_map : reg_width_deg_map;

    // Latch inputs on handshake
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            reg_in_data       <= {8*N_BYTES{1'b0}};
            reg_width_deg_map <= 3'b0;
        end else begin
            if (!mapper_en || !mode_active) begin
                reg_in_data       <= {8*N_BYTES{1'b0}};
                reg_width_deg_map <= 3'b0;
            end else if (handshake) begin
                reg_in_data       <= i_in_data;
                reg_width_deg_map <= i_width_deg_map;
            end
        end
    end

    // Helper for cycles needed per flit
    reg [2:0] cycles_needed;
    always_comb begin
        case (active_width_deg_map)
            DEGRADE_LANES_0_TO_15: cycles_needed = 3'd1;
            DEGRADE_LANES_0_TO_7,
            DEGRADE_LANES_8_TO_15: cycles_needed = 3'd2;
            DEGRADE_LANES_0_TO_3,
            DEGRADE_LANES_4_TO_7:  cycles_needed = 3'd4;
            default:               cycles_needed = 3'd1;
        endcase
    end

    //============================================================
    // Sequential Logic
    //============================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            cycle_count      <= 2'd0;
            out_scramble_en  <= 1'b0;
            mapper_ready     <= 1'b1; // Ready after reset!
            o_lane_0         <= {WIDTH{1'b0}};
            o_lane_1         <= {WIDTH{1'b0}};
            o_lane_2         <= {WIDTH{1'b0}};
            o_lane_3         <= {WIDTH{1'b0}};
            o_lane_4         <= {WIDTH{1'b0}};
            o_lane_5         <= {WIDTH{1'b0}};
            o_lane_6         <= {WIDTH{1'b0}};
            o_lane_7         <= {WIDTH{1'b0}};
            o_lane_8         <= {WIDTH{1'b0}};
            o_lane_9         <= {WIDTH{1'b0}};
            o_lane_10        <= {WIDTH{1'b0}};
            o_lane_11        <= {WIDTH{1'b0}};
            o_lane_12        <= {WIDTH{1'b0}};
            o_lane_13        <= {WIDTH{1'b0}};
            o_lane_14        <= {WIDTH{1'b0}};
            o_lane_15        <= {WIDTH{1'b0}};
        end
        else begin
            if (!mapper_en || !mode_active) begin
                // Idle / Non-active mode
                cycle_count      <= 2'd0;
                out_scramble_en  <= 1'b0;
                mapper_ready     <= 1'b1; // Ready when idle
                o_lane_0         <= {WIDTH{1'b0}};
                o_lane_1         <= {WIDTH{1'b0}};
                o_lane_2         <= {WIDTH{1'b0}};
                o_lane_3         <= {WIDTH{1'b0}};
                o_lane_4         <= {WIDTH{1'b0}};
                o_lane_5         <= {WIDTH{1'b0}};
                o_lane_6         <= {WIDTH{1'b0}};
                o_lane_7         <= {WIDTH{1'b0}};
                o_lane_8         <= {WIDTH{1'b0}};
                o_lane_9         <= {WIDTH{1'b0}};
                o_lane_10        <= {WIDTH{1'b0}};
                o_lane_11        <= {WIDTH{1'b0}};
                o_lane_12        <= {WIDTH{1'b0}};
                o_lane_13        <= {WIDTH{1'b0}};
                o_lane_14        <= {WIDTH{1'b0}};
                o_lane_15        <= {WIDTH{1'b0}};
            end
            else begin
                // Active mode & enabled
                if (!is_active) begin
                    // Stall mid-transaction or waiting for first transaction
                    out_scramble_en <= 1'b0;
                    o_lane_0         <= {WIDTH{1'b0}};
                    o_lane_1         <= {WIDTH{1'b0}};
                    o_lane_2         <= {WIDTH{1'b0}};
                    o_lane_3         <= {WIDTH{1'b0}};
                    o_lane_4         <= {WIDTH{1'b0}};
                    o_lane_5         <= {WIDTH{1'b0}};
                    o_lane_6         <= {WIDTH{1'b0}};
                    o_lane_7         <= {WIDTH{1'b0}};
                    o_lane_8         <= {WIDTH{1'b0}};
                    o_lane_9         <= {WIDTH{1'b0}};
                    o_lane_10        <= {WIDTH{1'b0}};
                    o_lane_11        <= {WIDTH{1'b0}};
                    o_lane_12        <= {WIDTH{1'b0}};
                    o_lane_13        <= {WIDTH{1'b0}};
                    o_lane_14        <= {WIDTH{1'b0}};
                    o_lane_15        <= {WIDTH{1'b0}};

                    // mapper_ready is HIGH if we are ready for a new flit
                    if (cycle_count == 2'd0 || cycle_count == cycles_needed - 1) begin
                        mapper_ready <= 1'b1;
                    end else begin
                        mapper_ready <= 1'b0;
                    end
                end
                else begin
                    // Real data active (is_active = 1)
                    out_scramble_en <= 1'b1;

                    // Clear all lanes as default, active ones will be overwritten in case statement
                    o_lane_0  <= {WIDTH{1'b0}};
                    o_lane_1  <= {WIDTH{1'b0}};
                    o_lane_2  <= {WIDTH{1'b0}};
                    o_lane_3  <= {WIDTH{1'b0}};
                    o_lane_4  <= {WIDTH{1'b0}};
                    o_lane_5  <= {WIDTH{1'b0}};
                    o_lane_6  <= {WIDTH{1'b0}};
                    o_lane_7  <= {WIDTH{1'b0}};
                    o_lane_8  <= {WIDTH{1'b0}};
                    o_lane_9  <= {WIDTH{1'b0}};
                    o_lane_10 <= {WIDTH{1'b0}};
                    o_lane_11 <= {WIDTH{1'b0}};
                    o_lane_12 <= {WIDTH{1'b0}};
                    o_lane_13 <= {WIDTH{1'b0}};
                    o_lane_14 <= {WIDTH{1'b0}};
                    o_lane_15 <= {WIDTH{1'b0}};

                    case (active_width_deg_map)
                        DEGRADE_LANES_0_TO_15: begin
                            o_lane_0  <= {active_data[391:384], active_data[263:256], active_data[135:128], active_data[  7:  0]};
                            o_lane_1  <= {active_data[399:392], active_data[271:264], active_data[143:136], active_data[ 15:  8]};
                            o_lane_2  <= {active_data[407:400], active_data[279:272], active_data[151:144], active_data[ 23: 16]};
                            o_lane_3  <= {active_data[415:408], active_data[287:280], active_data[159:152], active_data[ 31: 24]};
                            o_lane_4  <= {active_data[423:416], active_data[295:288], active_data[167:160], active_data[ 39: 32]};
                            o_lane_5  <= {active_data[431:424], active_data[303:296], active_data[175:168], active_data[ 47: 40]};
                            o_lane_6  <= {active_data[439:432], active_data[311:304], active_data[183:176], active_data[ 55: 48]};
                            o_lane_7  <= {active_data[447:440], active_data[319:312], active_data[191:184], active_data[ 63: 56]};
                            o_lane_8  <= {active_data[455:448], active_data[327:320], active_data[199:192], active_data[ 71: 64]};
                            o_lane_9  <= {active_data[463:456], active_data[335:328], active_data[207:200], active_data[ 79: 72]};
                            o_lane_10 <= {active_data[471:464], active_data[343:336], active_data[215:208], active_data[ 87: 80]};
                            o_lane_11 <= {active_data[479:472], active_data[351:344], active_data[223:216], active_data[ 95: 88]};
                            o_lane_12 <= {active_data[487:480], active_data[359:352], active_data[231:224], active_data[103: 96]};
                            o_lane_13 <= {active_data[495:488], active_data[367:360], active_data[239:232], active_data[111:104]};
                            o_lane_14 <= {active_data[503:496], active_data[375:368], active_data[247:240], active_data[119:112]};
                            o_lane_15 <= {active_data[511:504], active_data[383:376], active_data[255:248], active_data[127:120]};
                        end

                        DEGRADE_LANES_0_TO_7: begin
                            case (cycle_count)
                                2'd0: begin
                                    o_lane_0 <= {active_data[199:192], active_data[135:128], active_data[ 71: 64], active_data[  7:  0]};
                                    o_lane_1 <= {active_data[207:200], active_data[143:136], active_data[ 79: 72], active_data[ 15:  8]};
                                    o_lane_2 <= {active_data[215:208], active_data[151:144], active_data[ 87: 80], active_data[ 23: 16]};
                                    o_lane_3 <= {active_data[223:216], active_data[159:152], active_data[ 95: 88], active_data[ 31: 24]};
                                    o_lane_4 <= {active_data[231:224], active_data[167:160], active_data[103: 96], active_data[ 39: 32]};
                                    o_lane_5 <= {active_data[239:232], active_data[175:168], active_data[111:104], active_data[ 47: 40]};
                                    o_lane_6 <= {active_data[247:240], active_data[183:176], active_data[119:112], active_data[ 55: 48]};
                                    o_lane_7 <= {active_data[255:248], active_data[191:184], active_data[127:120], active_data[ 63: 56]};
                                end
                                2'd1: begin
                                    o_lane_0 <= {active_data[455:448], active_data[391:384], active_data[327:320], active_data[263:256]};
                                    o_lane_1 <= {active_data[463:456], active_data[399:392], active_data[335:328], active_data[271:264]};
                                    o_lane_2 <= {active_data[471:464], active_data[407:400], active_data[343:336], active_data[279:272]};
                                    o_lane_3 <= {active_data[479:472], active_data[415:408], active_data[351:344], active_data[287:280]};
                                    o_lane_4 <= {active_data[487:480], active_data[423:416], active_data[359:352], active_data[295:288]};
                                    o_lane_5 <= {active_data[495:488], active_data[431:424], active_data[367:360], active_data[303:296]};
                                    o_lane_6 <= {active_data[503:496], active_data[439:432], active_data[375:368], active_data[311:304]};
                                    o_lane_7 <= {active_data[511:504], active_data[447:440], active_data[383:376], active_data[319:312]};
                                end
                                default: begin end
                            endcase
                        end

                        DEGRADE_LANES_8_TO_15: begin
                            case (cycle_count)
                                2'd0: begin
                                    o_lane_8  <= {active_data[199:192], active_data[135:128], active_data[ 71: 64], active_data[  7:  0]};
                                    o_lane_9  <= {active_data[207:200], active_data[143:136], active_data[ 79: 72], active_data[ 15:  8]};
                                    o_lane_10 <= {active_data[215:208], active_data[151:144], active_data[ 87: 80], active_data[ 23: 16]};
                                    o_lane_11 <= {active_data[223:216], active_data[159:152], active_data[ 95: 88], active_data[ 31: 24]};
                                    o_lane_12 <= {active_data[231:224], active_data[167:160], active_data[103: 96], active_data[ 39: 32]};
                                    o_lane_13 <= {active_data[239:232], active_data[175:168], active_data[111:104], active_data[ 47: 40]};
                                    o_lane_14 <= {active_data[247:240], active_data[183:176], active_data[119:112], active_data[ 55: 48]};
                                    o_lane_15 <= {active_data[255:248], active_data[191:184], active_data[127:120], active_data[ 63: 56]};
                                end
                                2'd1: begin
                                    o_lane_8  <= {active_data[455:448], active_data[391:384], active_data[327:320], active_data[263:256]};
                                    o_lane_9  <= {active_data[463:456], active_data[399:392], active_data[335:328], active_data[271:264]};
                                    o_lane_10 <= {active_data[471:464], active_data[407:400], active_data[343:336], active_data[279:272]};
                                    o_lane_11 <= {active_data[479:472], active_data[415:408], active_data[351:344], active_data[287:280]};
                                    o_lane_12 <= {active_data[487:480], active_data[423:416], active_data[359:352], active_data[295:288]};
                                    o_lane_13 <= {active_data[495:488], active_data[431:424], active_data[367:360], active_data[303:296]};
                                    o_lane_14 <= {active_data[503:496], active_data[439:432], active_data[375:368], active_data[311:304]};
                                    o_lane_15 <= {active_data[511:504], active_data[447:440], active_data[383:376], active_data[319:312]};
                                end
                                default: begin end
                            endcase
                        end

                        DEGRADE_LANES_0_TO_3: begin
                            case (cycle_count)
                                2'd0: begin
                                    o_lane_0 <= {active_data[103: 96], active_data[ 71: 64], active_data[ 39: 32], active_data[  7:  0]};
                                    o_lane_1 <= {active_data[111:104], active_data[ 79: 72], active_data[ 47: 40], active_data[ 15:  8]};
                                    o_lane_2 <= {active_data[119:112], active_data[ 87: 80], active_data[ 55: 48], active_data[ 23: 16]};
                                    o_lane_3 <= {active_data[127:120], active_data[ 95: 88], active_data[ 63: 56], active_data[ 31: 24]};
                                end
                                2'd1: begin
                                    o_lane_0 <= {active_data[231:224], active_data[199:192], active_data[167:160], active_data[135:128]};
                                    o_lane_1 <= {active_data[239:232], active_data[207:200], active_data[175:168], active_data[143:136]};
                                    o_lane_2 <= {active_data[247:240], active_data[215:208], active_data[183:176], active_data[151:144]};
                                    o_lane_3 <= {active_data[255:248], active_data[223:216], active_data[191:184], active_data[159:152]};
                                end
                                2'd2: begin
                                    o_lane_0 <= {active_data[359:352], active_data[327:320], active_data[295:288], active_data[263:256]};
                                    o_lane_1 <= {active_data[367:360], active_data[335:328], active_data[303:296], active_data[271:264]};
                                    o_lane_2 <= {active_data[375:368], active_data[343:336], active_data[311:304], active_data[279:272]};
                                    o_lane_3 <= {active_data[383:376], active_data[351:344], active_data[319:312], active_data[287:280]};
                                end
                                2'd3: begin
                                    o_lane_0 <= {active_data[487:480], active_data[455:448], active_data[423:416], active_data[391:384]};
                                    o_lane_1 <= {active_data[495:488], active_data[463:456], active_data[431:424], active_data[399:392]};
                                    o_lane_2 <= {active_data[503:496], active_data[471:464], active_data[439:432], active_data[407:400]};
                                    o_lane_3 <= {active_data[511:504], active_data[479:472], active_data[447:440], active_data[415:408]};
                                end
                                default: begin end
                            endcase
                        end

                        DEGRADE_LANES_4_TO_7: begin
                            case (cycle_count)
                                2'd0: begin
                                    o_lane_4 <= {active_data[103: 96], active_data[ 71: 64], active_data[ 39: 32], active_data[  7:  0]};
                                    o_lane_5 <= {active_data[111:104], active_data[ 79: 72], active_data[ 47: 40], active_data[ 15:  8]};
                                    o_lane_6 <= {active_data[119:112], active_data[ 87: 80], active_data[ 55: 48], active_data[ 23: 16]};
                                    o_lane_7 <= {active_data[127:120], active_data[ 95: 88], active_data[ 63: 56], active_data[ 31: 24]};
                                end
                                2'd1: begin
                                    o_lane_4 <= {active_data[231:224], active_data[199:192], active_data[167:160], active_data[135:128]};
                                    o_lane_5 <= {active_data[239:232], active_data[207:200], active_data[175:168], active_data[143:136]};
                                    o_lane_6 <= {active_data[247:240], active_data[215:208], active_data[183:176], active_data[151:144]};
                                    o_lane_7 <= {active_data[255:248], active_data[223:216], active_data[191:184], active_data[159:152]};
                                end
                                2'd2: begin
                                    o_lane_4 <= {active_data[359:352], active_data[327:320], active_data[295:288], active_data[263:256]};
                                    o_lane_5 <= {active_data[367:360], active_data[335:328], active_data[303:296], active_data[271:264]};
                                    o_lane_6 <= {active_data[375:368], active_data[343:336], active_data[311:304], active_data[279:272]};
                                    o_lane_7 <= {active_data[383:376], active_data[351:344], active_data[319:312], active_data[287:280]};
                                end
                                2'd3: begin
                                    o_lane_4 <= {active_data[487:480], active_data[455:448], active_data[423:416], active_data[391:384]};
                                    o_lane_5 <= {active_data[495:488], active_data[463:456], active_data[431:424], active_data[399:392]};
                                    o_lane_6 <= {active_data[503:496], active_data[471:464], active_data[439:432], active_data[407:400]};
                                    o_lane_7 <= {active_data[511:504], active_data[479:472], active_data[447:440], active_data[415:408]};
                                end
                                default: begin end
                            endcase
                        end
                        default: begin end
                    endcase

                    // Update cycle_count and mapper_ready for the next clock cycle
                    if (cycle_count == cycles_needed - 1) begin
                        cycle_count  <= 2'd0;
                        mapper_ready <= 1'b1;
                    end else begin
                        cycle_count  <= cycle_count + 2'd1;
                        mapper_ready <= 1'b0;
                    end
                end
            end
        end
    end

endmodule