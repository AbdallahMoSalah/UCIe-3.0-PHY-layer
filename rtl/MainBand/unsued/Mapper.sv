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
    localparam NUM_WORDS       = N_BYTES / N_BYTE_PER_LANE;    // 16

    localparam CLOCK_CYCLES_16 = NUM_WORDS / 16;  // 1
    localparam CLOCK_CYCLES_8  = NUM_WORDS / 8;   // 2
    localparam CLOCK_CYCLES_4  = NUM_WORDS / 4;   // 4

    //============================================================
    // Skid Buffer (1-Entry)
    //============================================================
    // Cycle Counter
    //============================================================
    reg [1:0] cycle_count;

    //============================================================
    // Skid Buffer (1-Entry)
    //============================================================
    reg [8*N_BYTES-1:0] buf_data;
    reg                 buf_full;

    // Packet done determines when the transmission completes
    wire packet_done = buf_full && (
        ((i_width_deg_map == DEGRADE_LANES_0_TO_15) && (cycle_count == CLOCK_CYCLES_16 - 1)) ||
        (((i_width_deg_map == DEGRADE_LANES_0_TO_7) || (i_width_deg_map == DEGRADE_LANES_8_TO_15)) && (cycle_count == CLOCK_CYCLES_8 - 1)) ||
        (((i_width_deg_map == DEGRADE_LANES_0_TO_3) || (i_width_deg_map == DEGRADE_LANES_4_TO_7)) && (cycle_count == CLOCK_CYCLES_4 - 1)) ||
        // Fallback for safety on unsupported/default modes
        (i_width_deg_map != DEGRADE_LANES_0_TO_15 && 
         i_width_deg_map != DEGRADE_LANES_0_TO_7 && 
         i_width_deg_map != DEGRADE_LANES_8_TO_15 && 
         i_width_deg_map != DEGRADE_LANES_0_TO_3 && 
         i_width_deg_map != DEGRADE_LANES_4_TO_7)
    );

    // mapper_ready is high when buffer is empty or transmission is done
    assign mapper_ready = (mapper_en && i_rst_n) ? (!buf_full || packet_done) : 1'b0;

    // Push when input is valid and mapper is ready to accept
    wire push = lp_valid && lp_irdy && mapper_ready;

    wire pop = packet_done;

    // Skid Buffer Sequential Logic
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            buf_full <= 1'b0;
            buf_data <= {8*N_BYTES{1'b0}};
        end else if (mapper_en) begin
            if (push) begin
                buf_data <= i_in_data;
                buf_full <= 1'b1;
            end else if (pop) begin
                buf_full <= 1'b0;
            end
        end else begin
            buf_full <= 1'b0;
        end
    end

    // Cycle Counter Logic
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            cycle_count <= 2'd0;
        end else if (mapper_en) begin
            if (buf_full) begin
                if (packet_done) begin
                    cycle_count <= 2'd0;
                end else begin
                    cycle_count <= cycle_count + 1'b1;
                end
            end else begin
                cycle_count <= 2'd0;
            end
        end else begin
            cycle_count <= 2'd0;
        end
    end

    //============================================================
    // Outputs Logic (Scramble Enable and Lane Mapping)
    //============================================================
    wire [8*N_BYTES-1:0] map_src   = push ? i_in_data : buf_data;
    wire [1:0]           map_cycle = push ? 2'd0 : (cycle_count + 1'b1);

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            out_scramble_en <= 1'b0;
            o_lane_0        <= {WIDTH{1'b0}};
            o_lane_1        <= {WIDTH{1'b0}};
            o_lane_2        <= {WIDTH{1'b0}};
            o_lane_3        <= {WIDTH{1'b0}};
            o_lane_4        <= {WIDTH{1'b0}};
            o_lane_5        <= {WIDTH{1'b0}};
            o_lane_6        <= {WIDTH{1'b0}};
            o_lane_7        <= {WIDTH{1'b0}};
            o_lane_8        <= {WIDTH{1'b0}};
            o_lane_9        <= {WIDTH{1'b0}};
            o_lane_10       <= {WIDTH{1'b0}};
            o_lane_11       <= {WIDTH{1'b0}};
            o_lane_12       <= {WIDTH{1'b0}};
            o_lane_13       <= {WIDTH{1'b0}};
            o_lane_14       <= {WIDTH{1'b0}};
            o_lane_15       <= {WIDTH{1'b0}};
        end else if (mapper_en) begin
            if (push || (buf_full && !packet_done)) begin
                out_scramble_en <= 1'b1;
                case (i_width_deg_map)
                    
                    //================================================
                    // 16 Lanes Active — 1 cycle
                    //================================================
                    DEGRADE_LANES_0_TO_15: begin
                        o_lane_0  <= {map_src[391:384], map_src[263:256], map_src[135:128], map_src[  7:  0]};
                        o_lane_1  <= {map_src[399:392], map_src[271:264], map_src[143:136], map_src[ 15:  8]};
                        o_lane_2  <= {map_src[407:400], map_src[279:272], map_src[151:144], map_src[ 23: 16]};
                        o_lane_3  <= {map_src[415:408], map_src[287:280], map_src[159:152], map_src[ 31: 24]};
                        o_lane_4  <= {map_src[423:416], map_src[295:288], map_src[167:160], map_src[ 39: 32]};
                        o_lane_5  <= {map_src[431:424], map_src[303:296], map_src[175:168], map_src[ 47: 40]};
                        o_lane_6  <= {map_src[439:432], map_src[311:304], map_src[183:176], map_src[ 55: 48]};
                        o_lane_7  <= {map_src[447:440], map_src[319:312], map_src[191:184], map_src[ 63: 56]};
                        o_lane_8  <= {map_src[455:448], map_src[327:320], map_src[199:192], map_src[ 71: 64]};
                        o_lane_9  <= {map_src[463:456], map_src[335:328], map_src[207:200], map_src[ 79: 72]};
                        o_lane_10 <= {map_src[471:464], map_src[343:336], map_src[215:208], map_src[ 87: 80]};
                        o_lane_11 <= {map_src[479:472], map_src[351:344], map_src[223:216], map_src[ 95: 88]};
                        o_lane_12 <= {map_src[487:480], map_src[359:352], map_src[231:224], map_src[103: 96]};
                        o_lane_13 <= {map_src[495:488], map_src[367:360], map_src[239:232], map_src[111:104]};
                        o_lane_14 <= {map_src[503:496], map_src[375:368], map_src[247:240], map_src[119:112]};
                        o_lane_15 <= {map_src[511:504], map_src[383:376], map_src[255:248], map_src[127:120]};
                    end

                    //================================================
                    // Lanes 0→7 — 2 cycles
                    //================================================
                    DEGRADE_LANES_0_TO_7: begin
                        case (map_cycle)
                            2'd0: begin
                                o_lane_0 <= {map_src[199:192], map_src[135:128], map_src[ 71: 64], map_src[  7:  0]};
                                o_lane_1 <= {map_src[207:200], map_src[143:136], map_src[ 79: 72], map_src[ 15:  8]};
                                o_lane_2 <= {map_src[215:208], map_src[151:144], map_src[ 87: 80], map_src[ 23: 16]};
                                o_lane_3 <= {map_src[223:216], map_src[159:152], map_src[ 95: 88], map_src[ 31: 24]};
                                o_lane_4 <= {map_src[231:224], map_src[167:160], map_src[103: 96], map_src[ 39: 32]};
                                o_lane_5 <= {map_src[239:232], map_src[175:168], map_src[111:104], map_src[ 47: 40]};
                                o_lane_6 <= {map_src[247:240], map_src[183:176], map_src[119:112], map_src[ 55: 48]};
                                o_lane_7 <= {map_src[255:248], map_src[191:184], map_src[127:120], map_src[ 63: 56]};
                            end
                            2'd1: begin
                                o_lane_0 <= {map_src[455:448], map_src[391:384], map_src[327:320], map_src[263:256]};
                                o_lane_1 <= {map_src[463:456], map_src[399:392], map_src[335:328], map_src[271:264]};
                                o_lane_2 <= {map_src[471:464], map_src[407:400], map_src[343:336], map_src[279:272]};
                                o_lane_3 <= {map_src[479:472], map_src[415:408], map_src[351:344], map_src[287:280]};
                                o_lane_4 <= {map_src[487:480], map_src[423:416], map_src[359:352], map_src[295:288]};
                                o_lane_5 <= {map_src[495:488], map_src[431:424], map_src[367:360], map_src[303:296]};
                                o_lane_6 <= {map_src[503:496], map_src[439:432], map_src[375:368], map_src[311:304]};
                                o_lane_7 <= {map_src[511:504], map_src[447:440], map_src[383:376], map_src[319:312]};
                            end
                            default: begin end
                        endcase
                    end

                    //================================================
                    // Lanes 8→15 — 2 cycles
                    //================================================
                    DEGRADE_LANES_8_TO_15: begin
                        case (map_cycle)
                            2'd0: begin
                                o_lane_8  <= {map_src[199:192], map_src[135:128], map_src[ 71: 64], map_src[  7:  0]};
                                o_lane_9  <= {map_src[207:200], map_src[143:136], map_src[ 79: 72], map_src[ 15:  8]};
                                o_lane_10 <= {map_src[215:208], map_src[151:144], map_src[ 87: 80], map_src[ 23: 16]};
                                o_lane_11 <= {map_src[223:216], map_src[159:152], map_src[ 95: 88], map_src[ 31: 24]};
                                o_lane_12 <= {map_src[231:224], map_src[167:160], map_src[103: 96], map_src[ 39: 32]};
                                o_lane_13 <= {map_src[239:232], map_src[175:168], map_src[111:104], map_src[ 47: 40]};
                                o_lane_14 <= {map_src[247:240], map_src[183:176], map_src[119:112], map_src[ 55: 48]};
                                o_lane_15 <= {map_src[255:248], map_src[191:184], map_src[127:120], map_src[ 63: 56]};
                            end
                            2'd1: begin
                                o_lane_8  <= {map_src[455:448], map_src[391:384], map_src[327:320], map_src[263:256]};
                                o_lane_9  <= {map_src[463:456], map_src[399:392], map_src[335:328], map_src[271:264]};
                                o_lane_10 <= {map_src[471:464], map_src[407:400], map_src[343:336], map_src[279:272]};
                                o_lane_11 <= {map_src[479:472], map_src[415:408], map_src[351:344], map_src[287:280]};
                                o_lane_12 <= {map_src[487:480], map_src[423:416], map_src[359:352], map_src[295:288]};
                                o_lane_13 <= {map_src[495:488], map_src[431:424], map_src[367:360], map_src[303:296]};
                                o_lane_14 <= {map_src[503:496], map_src[439:432], map_src[375:368], map_src[311:304]};
                                o_lane_15 <= {map_src[511:504], map_src[447:440], map_src[383:376], map_src[319:312]};
                            end
                            default: begin end
                        endcase
                    end

                    //================================================
                    // Lanes 0→3 — 4 cycles
                    //================================================
                    DEGRADE_LANES_0_TO_3: begin
                        case (map_cycle)
                            2'd0: begin
                                o_lane_0 <= {map_src[103: 96], map_src[ 71: 64], map_src[ 39: 32], map_src[  7:  0]};
                                o_lane_1 <= {map_src[111:104], map_src[ 79: 72], map_src[ 47: 40], map_src[ 15:  8]};
                                o_lane_2 <= {map_src[119:112], map_src[ 87: 80], map_src[ 55: 48], map_src[ 23: 16]};
                                o_lane_3 <= {map_src[127:120], map_src[ 95: 88], map_src[ 63: 56], map_src[ 31: 24]};
                            end
                            2'd1: begin
                                o_lane_0 <= {map_src[231:224], map_src[199:192], map_src[167:160], map_src[135:128]};
                                o_lane_1 <= {map_src[239:232], map_src[207:200], map_src[175:168], map_src[143:136]};
                                o_lane_2 <= {map_src[247:240], map_src[215:208], map_src[183:176], map_src[151:144]};
                                o_lane_3 <= {map_src[255:248], map_src[223:216], map_src[191:184], map_src[159:152]};
                            end
                            2'd2: begin
                                o_lane_0 <= {map_src[359:352], map_src[327:320], map_src[295:288], map_src[263:256]};
                                o_lane_1 <= {map_src[367:360], map_src[335:328], map_src[303:296], map_src[271:264]};
                                o_lane_2 <= {map_src[375:368], map_src[343:336], map_src[311:304], map_src[279:272]};
                                o_lane_3 <= {map_src[383:376], map_src[351:344], map_src[319:312], map_src[287:280]};
                            end
                            2'd3: begin
                                o_lane_0 <= {map_src[487:480], map_src[455:448], map_src[423:416], map_src[391:384]};
                                o_lane_1 <= {map_src[495:488], map_src[463:456], map_src[431:424], map_src[399:392]};
                                o_lane_2 <= {map_src[503:496], map_src[471:464], map_src[439:432], map_src[407:400]};
                                o_lane_3 <= {map_src[511:504], map_src[479:472], map_src[447:440], map_src[415:408]};
                            end
                            default: begin end
                        endcase
                    end

                    //================================================
                    // Lanes 4→7 — 4 cycles
                    //================================================
                    DEGRADE_LANES_4_TO_7: begin
                        case (map_cycle)
                            2'd0: begin
                                o_lane_4 <= {map_src[103: 96], map_src[ 71: 64], map_src[ 39: 32], map_src[  7:  0]};
                                o_lane_5 <= {map_src[111:104], map_src[ 79: 72], map_src[ 47: 40], map_src[ 15:  8]};
                                o_lane_6 <= {map_src[119:112], map_src[ 87: 80], map_src[ 55: 48], map_src[ 23: 16]};
                                o_lane_7 <= {map_src[127:120], map_src[ 95: 88], map_src[ 63: 56], map_src[ 31: 24]};
                            end
                            2'd1: begin
                                o_lane_4 <= {map_src[231:224], map_src[199:192], map_src[167:160], map_src[135:128]};
                                o_lane_5 <= {map_src[239:232], map_src[207:200], map_src[175:168], map_src[143:136]};
                                o_lane_6 <= {map_src[247:240], map_src[215:208], map_src[183:176], map_src[151:144]};
                                o_lane_7 <= {map_src[255:248], map_src[223:216], map_src[191:184], map_src[159:152]};
                            end
                            2'd2: begin
                                o_lane_4 <= {map_src[359:352], map_src[327:320], map_src[295:288], map_src[263:256]};
                                o_lane_5 <= {map_src[367:360], map_src[335:328], map_src[303:296], map_src[271:264]};
                                o_lane_6 <= {map_src[375:368], map_src[343:336], map_src[311:304], map_src[279:272]};
                                o_lane_7 <= {map_src[383:376], map_src[351:344], map_src[319:312], map_src[287:280]};
                            end
                            2'd3: begin
                                o_lane_4 <= {map_src[487:480], map_src[455:448], map_src[423:416], map_src[391:384]};
                                o_lane_5 <= {map_src[495:488], map_src[463:456], map_src[431:424], map_src[399:392]};
                                o_lane_6 <= {map_src[503:496], map_src[471:464], map_src[439:432], map_src[407:400]};
                                o_lane_7 <= {map_src[511:504], map_src[479:472], map_src[447:440], map_src[415:408]};
                            end
                            default: begin end
                        endcase
                    end

                    default: begin end
                endcase
            end else begin
                out_scramble_en <= 1'b0;
                o_lane_0        <= {WIDTH{1'b0}};
                o_lane_1        <= {WIDTH{1'b0}};
                o_lane_2        <= {WIDTH{1'b0}};
                o_lane_3        <= {WIDTH{1'b0}};
                o_lane_4        <= {WIDTH{1'b0}};
                o_lane_5        <= {WIDTH{1'b0}};
                o_lane_6        <= {WIDTH{1'b0}};
                o_lane_7        <= {WIDTH{1'b0}};
                o_lane_8        <= {WIDTH{1'b0}};
                o_lane_9        <= {WIDTH{1'b0}};
                o_lane_10       <= {WIDTH{1'b0}};
                o_lane_11       <= {WIDTH{1'b0}};
                o_lane_12       <= {WIDTH{1'b0}};
                o_lane_13       <= {WIDTH{1'b0}};
                o_lane_14       <= {WIDTH{1'b0}};
                o_lane_15       <= {WIDTH{1'b0}};
            end
        end else begin
            out_scramble_en <= 1'b0;
            o_lane_0        <= {WIDTH{1'b0}};
            o_lane_1        <= {WIDTH{1'b0}};
            o_lane_2        <= {WIDTH{1'b0}};
            o_lane_3        <= {WIDTH{1'b0}};
            o_lane_4        <= {WIDTH{1'b0}};
            o_lane_5        <= {WIDTH{1'b0}};
            o_lane_6        <= {WIDTH{1'b0}};
            o_lane_7        <= {WIDTH{1'b0}};
            o_lane_8        <= {WIDTH{1'b0}};
            o_lane_9        <= {WIDTH{1'b0}};
            o_lane_10       <= {WIDTH{1'b0}};
            o_lane_11       <= {WIDTH{1'b0}};
            o_lane_12       <= {WIDTH{1'b0}};
            o_lane_13       <= {WIDTH{1'b0}};
            o_lane_14       <= {WIDTH{1'b0}};
            o_lane_15       <= {WIDTH{1'b0}};
        end
    end

endmodule
