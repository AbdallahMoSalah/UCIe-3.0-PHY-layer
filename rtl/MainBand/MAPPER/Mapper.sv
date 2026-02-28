module Mapper #(
    parameter WIDTH      = 32,
    parameter NUM_LANES  = 16,
    parameter N_BYTES    = 64
)(
    input  wire                     i_clk,
    input  wire                     i_rst_n,
    input  wire [8*N_BYTES-1:0]     i_in_data,
    input  wire                     mapper_en,
    input  wire [2:0]               i_width_deg_map,

    output reg  [WIDTH-1:0] o_lane_0,  o_lane_1,  o_lane_2,  o_lane_3,
    output reg  [WIDTH-1:0] o_lane_4,  o_lane_5,  o_lane_6,  o_lane_7,
    output reg  [WIDTH-1:0] o_lane_8,  o_lane_9,  o_lane_10, o_lane_11,
    output reg  [WIDTH-1:0] o_lane_12, o_lane_13, o_lane_14, o_lane_15
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
    localparam N_BYTE_PER_LANE = WIDTH / 8;
    localparam NUM_WORDS       = N_BYTES / N_BYTE_PER_LANE;  // 16 word 

    localparam CLOCK_CYCLES_16 = NUM_WORDS / 16; // 1 cycle 
    localparam CLOCK_CYCLES_8  = NUM_WORDS / 8; // 2 cycles 
    localparam CLOCK_CYCLES_4  = NUM_WORDS / 4; // 4 cycles 

    //============================================================
    // Internal Registers
    //============================================================
    reg [$clog2(CLOCK_CYCLES_4)-1:0] cycle_count;
    reg [WIDTH-1:0] lane_data [0:NUM_LANES-1] ; 
   
    //============================================================
    // Sequential Logic
    //============================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            cycle_count    <= 0;
            // Clear all lanes
            lane_data[0]   <= 0;
            lane_data[1]   <= 0;
            lane_data[2]   <= 0;
            lane_data[3]   <= 0;
            lane_data[4]   <= 0;
            lane_data[5]   <= 0;
            lane_data[6]   <= 0;
            lane_data[7]   <= 0;
            lane_data[8]   <= 0;
            lane_data[9]   <= 0;
            lane_data[10]  <= 0;
            lane_data[11]  <= 0;
            lane_data[12]  <= 0;
            lane_data[13]  <= 0;
            lane_data[14]  <= 0;
            lane_data[15]  <= 0;

        end
        else if (mapper_en) begin
            case (i_width_deg_map) 

            //====================================================
            // 16 Lanes Active
            //====================================================
            DEGRADE_LANES_0_TO_15: begin  // import 
                if (cycle_count < CLOCK_CYCLES_16) begin
                    if (cycle_count == 0) begin
                       
                            lane_data [0]  <= {i_in_data[7:0],    i_in_data[135:128],i_in_data[263:256], i_in_data[391:384]};
                            lane_data [1]  <= {i_in_data[15:8],   i_in_data[143:136],i_in_data[271:264],i_in_data[399:392]};
                            lane_data [2]  <= {i_in_data[23:16],  i_in_data[151:144], i_in_data[279:272], i_in_data[407:400]};
                            lane_data [3]  <= {i_in_data[31:24],  i_in_data[159:152], i_in_data[287:280], i_in_data[415:408]};
                            lane_data [4]  <= {i_in_data[39:32],  i_in_data[167:160], i_in_data[295:288], i_in_data[423:416]};
                            lane_data [5]  <= {i_in_data[47:40],  i_in_data[175:168], i_in_data[303:296], i_in_data[431:424]};
                            lane_data [6]  <= {i_in_data[55:48],  i_in_data[183:176], i_in_data[311:304], i_in_data[439:432]};
                            lane_data [7]  <= {i_in_data[63:56],  i_in_data[191:184], i_in_data[319:312], i_in_data[447:440]};
                            lane_data [8]  <= {i_in_data[71:64],  i_in_data[199:192], i_in_data[327:320], i_in_data[455:448]};
                            lane_data [9]  <= {i_in_data[79:72],  i_in_data[207:200], i_in_data[335:328], i_in_data[463:456]};
                            lane_data [10] <= {i_in_data[87:80],  i_in_data[215:208], i_in_data[343:336], i_in_data[471:464]};
                            lane_data [11] <= {i_in_data[95:88],  i_in_data[223:216], i_in_data[351:344], i_in_data[479:472]};
                            lane_data [12] <= {i_in_data[103:96], i_in_data[231:224], i_in_data[359:352], i_in_data[487:480]};
                            lane_data [13] <= {i_in_data[111:104],i_in_data[239:232], i_in_data[367:360], i_in_data[495:488]};
                            lane_data [14] <= {i_in_data[119:112],i_in_data[247:240], i_in_data[375:368], i_in_data[503:496]};
                            lane_data [15] <= {i_in_data[127:120],i_in_data[255:248], i_in_data[383:376], i_in_data[511:504]};  
                end
                cycle_count <= cycle_count + 1 ;
                 if (cycle_count == CLOCK_CYCLES_16) begin
                    cycle_count <=0;
                end
                end 
                end
            
            //====================================================
            // Lanes 0 → 7
            //====================================================
            DEGRADE_LANES_0_TO_7: begin
                if (cycle_count < CLOCK_CYCLES_8) begin
                    case (cycle_count ) 
                    0:begin
                    lane_data[0]  <= {i_in_data[7:0],    i_in_data[71:64],   i_in_data[135:128],  i_in_data[199:192]};
                    lane_data[1]  <= {i_in_data[15:8],   i_in_data[79:72],   i_in_data[143:136],  i_in_data[207:200]};
                    lane_data[2]  <= {i_in_data[23:16],  i_in_data[87:80],   i_in_data[151:144],  i_in_data[215:208]};
                    lane_data[3]  <= {i_in_data[31:24],  i_in_data[95:88],   i_in_data[159:152],  i_in_data[223:216]};
                    lane_data[4]  <= {i_in_data[39:32],  i_in_data[103:96],  i_in_data[167:160],  i_in_data[231:224]};
                    lane_data[5]  <= {i_in_data[47:40],  i_in_data[111:104], i_in_data[175:168],  i_in_data[239:232]};
                    lane_data[6]  <= {i_in_data[55:48],  i_in_data[119:112], i_in_data[183:176],  i_in_data[247:240]};
                    lane_data[7]  <= {i_in_data[63:56],  i_in_data[127:120], i_in_data[191:184],  i_in_data[255:248]};
                                        
                    end


                    1: begin
                        lane_data[0]  <= {i_in_data[263:256], i_in_data[327:320], i_in_data[391:384], i_in_data[455:448]};
                        lane_data[1]  <= {i_in_data[271:264], i_in_data[335:328], i_in_data[399:392], i_in_data[463:456]};
                        lane_data[2]  <= {i_in_data[279:272], i_in_data[343:336], i_in_data[407:400], i_in_data[471:464]};
                        lane_data[3]  <= {i_in_data[287:280], i_in_data[351:344], i_in_data[415:408], i_in_data[479:472]};
                        lane_data[4]  <= {i_in_data[295:288], i_in_data[359:352], i_in_data[423:416], i_in_data[487:480]};
                        lane_data[5]  <= {i_in_data[303:296], i_in_data[367:360], i_in_data[431:424], i_in_data[495:488]};
                        lane_data[6]  <= {i_in_data[311:304], i_in_data[375:368], i_in_data[439:432], i_in_data[503:496]};
                        lane_data[7]  <= {i_in_data[319:312], i_in_data[383:376], i_in_data[447:440], i_in_data[511:504]};
                    end
                    default: begin
        lane_data[0] <= 0;
        lane_data[1] <= 0;
        lane_data[2] <= 0;
        lane_data[3] <= 0;
        lane_data[4] <= 0;
        lane_data[5] <= 0;
        lane_data[6] <= 0;
        lane_data[7] <= 0;
    end
                    endcase
                    cycle_count <= cycle_count + 1;
                 if (cycle_count == CLOCK_CYCLES_8) begin
                    cycle_count <=0;
                end
                end
            
            end

            //====================================================
            // Lanes 8 → 15
            //====================================================
            DEGRADE_LANES_8_TO_15: begin
                
                    if (cycle_count <CLOCK_CYCLES_8 ) begin
                    case(cycle_count)
                     0: begin
                    lane_data[8]  <= {i_in_data[7:0],    i_in_data[71:64],   i_in_data[135:128],  i_in_data[199:192]};
                    lane_data[9]  <= {i_in_data[15:8],   i_in_data[79:72],   i_in_data[143:136],  i_in_data[207:200]};
                    lane_data[10]  <= {i_in_data[23:16],  i_in_data[87:80],   i_in_data[151:144],  i_in_data[215:208]};
                    lane_data[11]  <= {i_in_data[31:24],  i_in_data[95:88],   i_in_data[159:152],  i_in_data[223:216]};
                    lane_data[12]  <= {i_in_data[39:32],  i_in_data[103:96],  i_in_data[167:160],  i_in_data[231:224]};
                    lane_data[13]  <= {i_in_data[47:40],  i_in_data[111:104], i_in_data[175:168],  i_in_data[239:232]};
                    lane_data[14]  <= {i_in_data[55:48],  i_in_data[119:112], i_in_data[183:176],  i_in_data[247:240]};
                    lane_data[15]  <= {i_in_data[63:56],  i_in_data[127:120], i_in_data[191:184],  i_in_data[255:248]};
                                        
                    end


                     1: begin
                        lane_data[8]  <= {i_in_data[263:256], i_in_data[327:320], i_in_data[391:384], i_in_data[455:448]};
                        lane_data[9]  <= {i_in_data[271:264], i_in_data[335:328], i_in_data[399:392], i_in_data[463:456]};
                        lane_data[10]  <= {i_in_data[279:272], i_in_data[343:336], i_in_data[407:400], i_in_data[471:464]};
                        lane_data[11]  <= {i_in_data[287:280], i_in_data[351:344], i_in_data[415:408], i_in_data[479:472]};
                        lane_data[12]  <= {i_in_data[295:288], i_in_data[359:352], i_in_data[423:416], i_in_data[487:480]};
                        lane_data[13]  <= {i_in_data[303:296], i_in_data[367:360], i_in_data[431:424], i_in_data[495:488]};
                        lane_data[14]  <= {i_in_data[311:304], i_in_data[375:368], i_in_data[439:432], i_in_data[503:496]};
                        lane_data[15]  <= {i_in_data[319:312], i_in_data[383:376], i_in_data[447:440], i_in_data[511:504]};
                    end
                    default: begin
        lane_data[8]  <= 0;
        lane_data[9]  <= 0;
        lane_data[10] <= 0;
        lane_data[11] <= 0;
        lane_data[12] <= 0;
        lane_data[13] <= 0;
        lane_data[14] <= 0;
        lane_data[15] <= 0;
    end
                    endcase
                    cycle_count <= cycle_count + 1;
                 if (cycle_count == CLOCK_CYCLES_8) begin
                    cycle_count <=0;
                end
                end
                end

            //====================================================
            // Lanes 0 → 3
            //====================================================
           DEGRADE_LANES_0_TO_3: begin
    if (cycle_count < CLOCK_CYCLES_4) begin  // 4 cycles
        case(cycle_count)
            0: begin
                lane_data[0] <= {i_in_data[7:0],   i_in_data[39:32],  i_in_data[71:64],  i_in_data[103:96]};
                lane_data[1] <= {i_in_data[15:8],  i_in_data[47:40],  i_in_data[79:72],  i_in_data[111:104]};
                lane_data[2] <= {i_in_data[23:16], i_in_data[55:48],  i_in_data[87:80],  i_in_data[119:112]};
                lane_data[3] <= {i_in_data[31:24], i_in_data[63:56],  i_in_data[95:88],  i_in_data[127:120]};
            end
            1: begin
                lane_data[0] <= {i_in_data[135:128], i_in_data[167:160], i_in_data[199:192], i_in_data[231:224]};
                lane_data[1] <= {i_in_data[143:136], i_in_data[175:168], i_in_data[207:200], i_in_data[239:232]};
                lane_data[2] <= {i_in_data[151:144], i_in_data[183:176], i_in_data[215:208], i_in_data[247:240]};
                lane_data[3] <= {i_in_data[159:152], i_in_data[191:184], i_in_data[223:216], i_in_data[255:248]};
            end
            2: begin
                lane_data[0] <= {i_in_data[263:256], i_in_data[295:288], i_in_data[327:320], i_in_data[359:352]};
                lane_data[1] <= {i_in_data[271:264], i_in_data[303:296], i_in_data[335:328], i_in_data[367:360]};
                lane_data[2] <= {i_in_data[279:272], i_in_data[311:304], i_in_data[343:336], i_in_data[375:368]};
                lane_data[3] <= {i_in_data[287:280], i_in_data[319:312], i_in_data[351:344], i_in_data[383:376]};
            end
            3: begin
                lane_data[0] <= {i_in_data[391:384], i_in_data[423:416], i_in_data[455:448], i_in_data[487:480]};
                lane_data[1] <= {i_in_data[399:392], i_in_data[431:424], i_in_data[463:456], i_in_data[495:488]};
                lane_data[2] <= {i_in_data[407:400], i_in_data[439:432], i_in_data[471:464], i_in_data[503:496]};
                lane_data[3] <= {i_in_data[415:408], i_in_data[447:440], i_in_data[479:472], i_in_data[511:504]};
            end
        default: begin
        lane_data[0] <= 0;
        lane_data[1] <= 0;
        lane_data[2] <= 0;
        lane_data[3] <= 0;

    end
        endcase
        cycle_count <= cycle_count + 1;
         if (cycle_count == CLOCK_CYCLES_4) begin
                    cycle_count <=0;
                  
            end
            end
            end

            //====================================================
            // Lanes 4 → 7
            DEGRADE_LANES_4_TO_7: begin
    if (cycle_count < CLOCK_CYCLES_4) begin  // 4 cycles
        case(cycle_count)
            0: begin
                lane_data[4] <= {i_in_data[7:0],   i_in_data[39:32],  i_in_data[71:64],  i_in_data[103:96]};
                lane_data[5] <= {i_in_data[15:8],  i_in_data[47:40],  i_in_data[79:72],  i_in_data[111:104]};
                lane_data[6] <= {i_in_data[23:16], i_in_data[55:48],  i_in_data[87:80],  i_in_data[119:112]};
                lane_data[7] <= {i_in_data[31:24], i_in_data[63:56],  i_in_data[95:88],  i_in_data[127:120]};
            end
            1: begin
                lane_data[4] <= {i_in_data[135:128], i_in_data[167:160], i_in_data[199:192], i_in_data[231:224]};
                lane_data[5] <= {i_in_data[143:136], i_in_data[175:168], i_in_data[207:200], i_in_data[239:232]};
                lane_data[6] <= {i_in_data[151:144], i_in_data[183:176], i_in_data[215:208], i_in_data[247:240]};
                lane_data[7] <= {i_in_data[159:152], i_in_data[191:184], i_in_data[223:216], i_in_data[255:248]};
            end
            2: begin
                lane_data[4] <= {i_in_data[263:256], i_in_data[295:288], i_in_data[327:320], i_in_data[359:352]};
                lane_data[5] <= {i_in_data[271:264], i_in_data[303:296], i_in_data[335:328], i_in_data[367:360]};
                lane_data[6] <= {i_in_data[279:272], i_in_data[311:304], i_in_data[343:336], i_in_data[375:368]};
                lane_data[7] <= {i_in_data[287:280], i_in_data[319:312], i_in_data[351:344], i_in_data[383:376]};
            end
            3: begin
                lane_data[4] <= {i_in_data[391:384], i_in_data[423:416], i_in_data[455:448], i_in_data[487:480]};
                lane_data[5] <= {i_in_data[399:392], i_in_data[431:424], i_in_data[463:456], i_in_data[495:488]};
                lane_data[6] <= {i_in_data[407:400], i_in_data[439:432], i_in_data[471:464], i_in_data[503:496]};
                lane_data[7] <= {i_in_data[415:408], i_in_data[447:440], i_in_data[479:472], i_in_data[511:504]};
            end
        default: begin
        lane_data[4] <= 0;
        lane_data[5] <= 0;
        lane_data[6] <= 0;
        lane_data[7] <= 0;
    end
        endcase
        cycle_count <= cycle_count + 1;
     if (cycle_count == CLOCK_CYCLES_4) begin
                    cycle_count <=0;
                end
    
              end
              end

            default: begin
            cycle_count    <= 0;
            // clear data 
            lane_data[0]   <= 0;
            lane_data[1]   <= 0;
            lane_data[2]   <= 0;
            lane_data[3]   <= 0;
            lane_data[4]   <= 0;
            lane_data[5]   <= 0;
            lane_data[6]   <= 0;
            lane_data[7]   <= 0;
            lane_data[8]   <= 0;
            lane_data[9]   <= 0;
            lane_data[10]  <= 0;
            lane_data[11]  <= 0;
            lane_data[12]  <= 0;
            lane_data[13]  <= 0;
            lane_data[14]  <= 0;
            lane_data[15]  <= 0;
            end
            endcase
        end
        else begin
            // IDLE state
            cycle_count     <= 0;
            //clear data 
            lane_data[0]    <= 0;
            lane_data[1]    <= 0;
            lane_data[2]    <= 0;
            lane_data[3]    <= 0;
            lane_data[4]    <= 0;
            lane_data[5]    <= 0;
            lane_data[6]    <= 0;
            lane_data[7]    <= 0;
            lane_data[8]    <= 0;
            lane_data[9]    <= 0;
            lane_data[10]   <= 0;
            lane_data[11]   <= 0;
            lane_data[12]   <= 0;
            lane_data[13]   <= 0;
            lane_data[14]   <= 0;
            lane_data[15]   <= 0;
            end
    end
    
    //============================================================
    // Output Assignment
    //============================================================
    always @(*) begin // alwas_com
        o_lane_0  = lane_data[0];
        o_lane_1  = lane_data[1];
        o_lane_2  = lane_data[2];
        o_lane_3  = lane_data[3];
        o_lane_4  = lane_data[4];
        o_lane_5  = lane_data[5];
        o_lane_6  = lane_data[6];
        o_lane_7  = lane_data[7];
        o_lane_8  = lane_data[8];
        o_lane_9  = lane_data[9];
        o_lane_10 = lane_data[10];
        o_lane_11 = lane_data[11];
        o_lane_12 = lane_data[12];
        o_lane_13 = lane_data[13];
        o_lane_14 = lane_data[14];
        o_lane_15 = lane_data[15];
    end

endmodule