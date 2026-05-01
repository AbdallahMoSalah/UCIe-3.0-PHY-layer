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
    output reg              mapper_ready // pl_
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
    localparam NUM_WORDS       = N_BYTES / N_BYTE_PER_LANE;    // 16

    localparam CLOCK_CYCLES_16 = NUM_WORDS / 16;  // 1
    localparam CLOCK_CYCLES_8  = NUM_WORDS / 8;   // 2
    localparam CLOCK_CYCLES_4  = NUM_WORDS / 4;   // 4

    //============================================================
    // Internal Registers
    //============================================================
    // cycle_count needs to count up to CLOCK_CYCLES_4-1 = 3 → 2 bits
    reg [1:0] cycle_count;

    // Active (lp_irdy && lp_valid): adapter has valid data and wants PL to sample
    wire data_active = lp_irdy && lp_valid;

    //============================================================
    // Sequential Logic
    //============================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            cycle_count   <= 2'd0;
            out_scramble_en      <= 1'b0;
            mapper_ready  <= 1'b0;
            o_lane_0      <= {WIDTH{1'b0}};
            o_lane_1      <= {WIDTH{1'b0}};
            o_lane_2      <= {WIDTH{1'b0}};
            o_lane_3      <= {WIDTH{1'b0}};
            o_lane_4      <= {WIDTH{1'b0}};
            o_lane_5      <= {WIDTH{1'b0}};
            o_lane_6      <= {WIDTH{1'b0}};
            o_lane_7      <= {WIDTH{1'b0}};
            o_lane_8      <= {WIDTH{1'b0}};
            o_lane_9      <= {WIDTH{1'b0}};
            o_lane_10     <= {WIDTH{1'b0}};
            o_lane_11     <= {WIDTH{1'b0}};
            o_lane_12     <= {WIDTH{1'b0}};
            o_lane_13     <= {WIDTH{1'b0}};
            o_lane_14     <= {WIDTH{1'b0}};
            o_lane_15     <= {WIDTH{1'b0}};
        end
        else begin
            // Default: clear done every cycle; it pulses for 1 cycle
            out_scramble_en     <= 1'b0;
            mapper_ready <= 1'b0;

            if (mapper_en && data_active) begin
                // Clear all lanes first to avoid stale data
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

                case (i_width_deg_map)
                
                    //================================================
                    // 16 Lanes Active — 1 cycle
                    //================================================
                    DEGRADE_LANES_0_TO_15: begin
                        o_lane_0  <= {i_in_data[  7:  0], i_in_data[135:128], i_in_data[263:256], i_in_data[391:384]};
                        o_lane_1  <= {i_in_data[ 15:  8], i_in_data[143:136], i_in_data[271:264], i_in_data[399:392]};
                        o_lane_2  <= {i_in_data[ 23: 16], i_in_data[151:144], i_in_data[279:272], i_in_data[407:400]};
                        o_lane_3  <= {i_in_data[ 31: 24], i_in_data[159:152], i_in_data[287:280], i_in_data[415:408]};
                        o_lane_4  <= {i_in_data[ 39: 32], i_in_data[167:160], i_in_data[295:288], i_in_data[423:416]};
                        o_lane_5  <= {i_in_data[ 47: 40], i_in_data[175:168], i_in_data[303:296], i_in_data[431:424]};
                        o_lane_6  <= {i_in_data[ 55: 48], i_in_data[183:176], i_in_data[311:304], i_in_data[439:432]};
                        o_lane_7  <= {i_in_data[ 63: 56], i_in_data[191:184], i_in_data[319:312], i_in_data[447:440]};
                        o_lane_8  <= {i_in_data[ 71: 64], i_in_data[199:192], i_in_data[327:320], i_in_data[455:448]};
                        o_lane_9  <= {i_in_data[ 79: 72], i_in_data[207:200], i_in_data[335:328], i_in_data[463:456]};
                        o_lane_10 <= {i_in_data[ 87: 80], i_in_data[215:208], i_in_data[343:336], i_in_data[471:464]};
                        o_lane_11 <= {i_in_data[ 95: 88], i_in_data[223:216], i_in_data[351:344], i_in_data[479:472]};
                        o_lane_12 <= {i_in_data[103: 96], i_in_data[231:224], i_in_data[359:352], i_in_data[487:480]};
                        o_lane_13 <= {i_in_data[111:104], i_in_data[239:232], i_in_data[367:360], i_in_data[495:488]};
                        o_lane_14 <= {i_in_data[119:112], i_in_data[247:240], i_in_data[375:368], i_in_data[503:496]};
                        o_lane_15 <= {i_in_data[127:120], i_in_data[255:248], i_in_data[383:376], i_in_data[511:504]};
                    
                        if (cycle_count == CLOCK_CYCLES_16 - 1) begin
                            cycle_count <= 2'd0;
                            out_scramble_en <= 1'b1;
                            mapper_ready <= 1'b1;
                        end
                        else begin
                            cycle_count <= cycle_count + 1;
                        end
                    end

                    //================================================
                    // Lanes 0→7 — 2 cycles
                    //================================================
                    DEGRADE_LANES_0_TO_7: begin
                        case (cycle_count)
                            2'd0: begin
                                o_lane_0 <= {i_in_data[  7:  0], i_in_data[ 71: 64], i_in_data[135:128], i_in_data[199:192]};
                                o_lane_1 <= {i_in_data[ 15:  8], i_in_data[ 79: 72], i_in_data[143:136], i_in_data[207:200]};
                                o_lane_2 <= {i_in_data[ 23: 16], i_in_data[ 87: 80], i_in_data[151:144], i_in_data[215:208]};
                                o_lane_3 <= {i_in_data[ 31: 24], i_in_data[ 95: 88], i_in_data[159:152], i_in_data[223:216]};
                                o_lane_4 <= {i_in_data[ 39: 32], i_in_data[103: 96], i_in_data[167:160], i_in_data[231:224]};
                                o_lane_5 <= {i_in_data[ 47: 40], i_in_data[111:104], i_in_data[175:168], i_in_data[239:232]};
                                o_lane_6 <= {i_in_data[ 55: 48], i_in_data[119:112], i_in_data[183:176], i_in_data[247:240]};
                                o_lane_7 <= {i_in_data[ 63: 56], i_in_data[127:120], i_in_data[191:184], i_in_data[255:248]};
                            end
                            2'd1: begin
                                o_lane_0 <= {i_in_data[263:256], i_in_data[327:320], i_in_data[391:384], i_in_data[455:448]};
                                o_lane_1 <= {i_in_data[271:264], i_in_data[335:328], i_in_data[399:392], i_in_data[463:456]};
                                o_lane_2 <= {i_in_data[279:272], i_in_data[343:336], i_in_data[407:400], i_in_data[471:464]};
                                o_lane_3 <= {i_in_data[287:280], i_in_data[351:344], i_in_data[415:408], i_in_data[479:472]};
                                o_lane_4 <= {i_in_data[295:288], i_in_data[359:352], i_in_data[423:416], i_in_data[487:480]};
                                o_lane_5 <= {i_in_data[303:296], i_in_data[367:360], i_in_data[431:424], i_in_data[495:488]};
                                o_lane_6 <= {i_in_data[311:304], i_in_data[375:368], i_in_data[439:432], i_in_data[503:496]};
                                o_lane_7 <= {i_in_data[319:312], i_in_data[383:376], i_in_data[447:440], i_in_data[511:504]};
                            end
                            default: begin end
                        endcase

                        if (cycle_count == CLOCK_CYCLES_8 - 1) begin
                            cycle_count <= 2'd0;
                            out_scramble_en <= 1'b1;
                            mapper_ready <= 1'b1;
                        end
                        else begin
                            cycle_count <= cycle_count + 1;
                        end
                    end

                    //================================================
                    // Lanes 8→15 — 2 cycles
                    //================================================
                    DEGRADE_LANES_8_TO_15: begin
                        case (cycle_count)
                            2'd0: begin
                                o_lane_8  <= {i_in_data[  7:  0], i_in_data[ 71: 64], i_in_data[135:128], i_in_data[199:192]};
                                o_lane_9  <= {i_in_data[ 15:  8], i_in_data[ 79: 72], i_in_data[143:136], i_in_data[207:200]};
                                o_lane_10 <= {i_in_data[ 23: 16], i_in_data[ 87: 80], i_in_data[151:144], i_in_data[215:208]};
                                o_lane_11 <= {i_in_data[ 31: 24], i_in_data[ 95: 88], i_in_data[159:152], i_in_data[223:216]};
                                o_lane_12 <= {i_in_data[ 39: 32], i_in_data[103: 96], i_in_data[167:160], i_in_data[231:224]};
                                o_lane_13 <= {i_in_data[ 47: 40], i_in_data[111:104], i_in_data[175:168], i_in_data[239:232]};
                                o_lane_14 <= {i_in_data[ 55: 48], i_in_data[119:112], i_in_data[183:176], i_in_data[247:240]};
                                o_lane_15 <= {i_in_data[ 63: 56], i_in_data[127:120], i_in_data[191:184], i_in_data[255:248]};
                            end
                            2'd1: begin
                                o_lane_8  <= {i_in_data[263:256], i_in_data[327:320], i_in_data[391:384], i_in_data[455:448]};
                                o_lane_9  <= {i_in_data[271:264], i_in_data[335:328], i_in_data[399:392], i_in_data[463:456]};
                                o_lane_10 <= {i_in_data[279:272], i_in_data[343:336], i_in_data[407:400], i_in_data[471:464]};
                                o_lane_11 <= {i_in_data[287:280], i_in_data[351:344], i_in_data[415:408], i_in_data[479:472]};
                                o_lane_12 <= {i_in_data[295:288], i_in_data[359:352], i_in_data[423:416], i_in_data[487:480]};
                                o_lane_13 <= {i_in_data[303:296], i_in_data[367:360], i_in_data[431:424], i_in_data[495:488]};
                                o_lane_14 <= {i_in_data[311:304], i_in_data[375:368], i_in_data[439:432], i_in_data[503:496]};
                                o_lane_15 <= {i_in_data[319:312], i_in_data[383:376], i_in_data[447:440], i_in_data[511:504]};
                            end
                            default: begin end
                        endcase

                        if (cycle_count == CLOCK_CYCLES_8 - 1) begin
                            cycle_count <= 2'd0;
                            out_scramble_en <= 1'b1;
                            mapper_ready <= 1'b1;
                        end
                        else begin
                            cycle_count <= cycle_count + 1;
                        end
                    end

                    //================================================
                    // Lanes 0→3 — 4 cycles
                    //================================================
                    DEGRADE_LANES_0_TO_3: begin
                        case (cycle_count)
                            2'd0: begin
                                o_lane_0 <= {i_in_data[  7:  0], i_in_data[ 39: 32], i_in_data[ 71: 64], i_in_data[103: 96]};
                                o_lane_1 <= {i_in_data[ 15:  8], i_in_data[ 47: 40], i_in_data[ 79: 72], i_in_data[111:104]};
                                o_lane_2 <= {i_in_data[ 23: 16], i_in_data[ 55: 48], i_in_data[ 87: 80], i_in_data[119:112]};
                                o_lane_3 <= {i_in_data[ 31: 24], i_in_data[ 63: 56], i_in_data[ 95: 88], i_in_data[127:120]};
                            end
                            2'd1: begin
                                o_lane_0 <= {i_in_data[135:128], i_in_data[167:160], i_in_data[199:192], i_in_data[231:224]};
                                o_lane_1 <= {i_in_data[143:136], i_in_data[175:168], i_in_data[207:200], i_in_data[239:232]};
                                o_lane_2 <= {i_in_data[151:144], i_in_data[183:176], i_in_data[215:208], i_in_data[247:240]};
                                o_lane_3 <= {i_in_data[159:152], i_in_data[191:184], i_in_data[223:216], i_in_data[255:248]};
                            end
                            2'd2: begin
                                o_lane_0 <= {i_in_data[263:256], i_in_data[295:288], i_in_data[327:320], i_in_data[359:352]};
                                o_lane_1 <= {i_in_data[271:264], i_in_data[303:296], i_in_data[335:328], i_in_data[367:360]};
                                o_lane_2 <= {i_in_data[279:272], i_in_data[311:304], i_in_data[343:336], i_in_data[375:368]};
                                o_lane_3 <= {i_in_data[287:280], i_in_data[319:312], i_in_data[351:344], i_in_data[383:376]};
                            end
                            2'd3: begin
                                o_lane_0 <= {i_in_data[391:384], i_in_data[423:416], i_in_data[455:448], i_in_data[487:480]};
                                o_lane_1 <= {i_in_data[399:392], i_in_data[431:424], i_in_data[463:456], i_in_data[495:488]};
                                o_lane_2 <= {i_in_data[407:400], i_in_data[439:432], i_in_data[471:464], i_in_data[503:496]};
                                o_lane_3 <= {i_in_data[415:408], i_in_data[447:440], i_in_data[479:472], i_in_data[511:504]};
                            end
                            default: begin end
                        endcase

                        if (cycle_count == CLOCK_CYCLES_4 - 1) begin
                            cycle_count <= 2'd0;
                            out_scramble_en <= 1'b1;
                            mapper_ready <= 1'b1;
                        end
                        else begin
                            cycle_count <= cycle_count + 1;
                        end
                    end

                    //================================================
                    // Lanes 4→7 — 4 cycles
                    //================================================
                    DEGRADE_LANES_4_TO_7: begin
                        case (cycle_count)
                            2'd0: begin
                                o_lane_4 <= {i_in_data[  7:  0], i_in_data[ 39: 32], i_in_data[ 71: 64], i_in_data[103: 96]};
                                o_lane_5 <= {i_in_data[ 15:  8], i_in_data[ 47: 40], i_in_data[ 79: 72], i_in_data[111:104]};
                                o_lane_6 <= {i_in_data[ 23: 16], i_in_data[ 55: 48], i_in_data[ 87: 80], i_in_data[119:112]};
                                o_lane_7 <= {i_in_data[ 31: 24], i_in_data[ 63: 56], i_in_data[ 95: 88], i_in_data[127:120]};
                            end
                            2'd1: begin
                                o_lane_4 <= {i_in_data[135:128], i_in_data[167:160], i_in_data[199:192], i_in_data[231:224]};
                                o_lane_5 <= {i_in_data[143:136], i_in_data[175:168], i_in_data[207:200], i_in_data[239:232]};
                                o_lane_6 <= {i_in_data[151:144], i_in_data[183:176], i_in_data[215:208], i_in_data[247:240]};
                                o_lane_7 <= {i_in_data[159:152], i_in_data[191:184], i_in_data[223:216], i_in_data[255:248]};
                            end
                            2'd2: begin
                                o_lane_4 <= {i_in_data[263:256], i_in_data[295:288], i_in_data[327:320], i_in_data[359:352]};
                                o_lane_5 <= {i_in_data[271:264], i_in_data[303:296], i_in_data[335:328], i_in_data[367:360]};
                                o_lane_6 <= {i_in_data[279:272], i_in_data[311:304], i_in_data[343:336], i_in_data[375:368]};
                                o_lane_7 <= {i_in_data[287:280], i_in_data[319:312], i_in_data[351:344], i_in_data[383:376]};
                            end
                            2'd3: begin
                                o_lane_4 <= {i_in_data[391:384], i_in_data[423:416], i_in_data[455:448], i_in_data[487:480]};
                                o_lane_5 <= {i_in_data[399:392], i_in_data[431:424], i_in_data[463:456], i_in_data[495:488]};
                                o_lane_6 <= {i_in_data[407:400], i_in_data[439:432], i_in_data[471:464], i_in_data[503:496]};
                                o_lane_7 <= {i_in_data[415:408], i_in_data[447:440], i_in_data[479:472], i_in_data[511:504]};
                            end
                            default: begin end
                        endcase

                        if (cycle_count == CLOCK_CYCLES_4 - 1) begin
                            cycle_count <= 2'd0;
                            out_scramble_en <= 1'b1;
                            mapper_ready <= 1'b1;
                        end
                        else begin 
                            cycle_count <= cycle_count + 1;
                        end
                    end

                    default: begin
                        cycle_count <= 2'd0;
                    end
                endcase
            end
            else if (!mapper_en) begin
                // IDLE — reset everything
                cycle_count   <= 2'd0;
                o_lane_0      <= {WIDTH{1'b0}};
                o_lane_1      <= {WIDTH{1'b0}};
                o_lane_2      <= {WIDTH{1'b0}};
                o_lane_3      <= {WIDTH{1'b0}};
                o_lane_4      <= {WIDTH{1'b0}};
                o_lane_5      <= {WIDTH{1'b0}};
                o_lane_6      <= {WIDTH{1'b0}};
                o_lane_7      <= {WIDTH{1'b0}};
                o_lane_8      <= {WIDTH{1'b0}};
                o_lane_9      <= {WIDTH{1'b0}};
                o_lane_10     <= {WIDTH{1'b0}};
                o_lane_11     <= {WIDTH{1'b0}};
                o_lane_12     <= {WIDTH{1'b0}};
                o_lane_13     <= {WIDTH{1'b0}};
                o_lane_14     <= {WIDTH{1'b0}};
                o_lane_15     <= {WIDTH{1'b0}};
            end
            // else: mapper_en=1 but data_active=0 → stall (hold outputs, hold cycle_count)
        end
    end

endmodule
