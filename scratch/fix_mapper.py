import sys

file_path = r"d:\Final_project\UCIE_CODES\UCIe-3.0-PHY-layer\rtl\MainBand\MAPPER\Mapper.sv"

with open(file_path, "r", encoding="utf-8") as f:
    lines = f.readlines()

# Fix mapper_ready declaration
for i, line in enumerate(lines):
    if "output reg mapper_ready" in line:
        lines[i] = line.replace("output reg mapper_ready", "output wire mapper_ready")

# Replace sequential block
new_block = """    //============================================================
    // Sequential Logic
    //============================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            cycle_count    <= 0;
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
            out_done       <= 0; 
        end
        else if (mapper_en) begin
            if (lp_irdy && lp_valid) begin
                // Default unused lanes to 0 to prevent stale data
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

                case (i_width_deg_map) 

                //====================================================
                // 16 Lanes Active
                //====================================================
                DEGRADE_LANES_0_TO_15: begin
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
                    
                    if (cycle_count == CLOCK_CYCLES_16 - 1) begin
                        cycle_count <= 0;
                        out_done    <= 1;
                    end else begin
                        cycle_count <= cycle_count + 1;
                        out_done    <= 0;
                    end
                end
                
                //====================================================
                // Lanes 0 → 7
                //====================================================
                DEGRADE_LANES_0_TO_7: begin
                    if (cycle_count == 0) begin
                        lane_data[0]  <= {i_in_data[7:0],    i_in_data[71:64],   i_in_data[135:128],  i_in_data[199:192]};
                        lane_data[1]  <= {i_in_data[15:8],   i_in_data[79:72],   i_in_data[143:136],  i_in_data[207:200]};
                        lane_data[2]  <= {i_in_data[23:16],  i_in_data[87:80],   i_in_data[151:144],  i_in_data[215:208]};
                        lane_data[3]  <= {i_in_data[31:24],  i_in_data[95:88],   i_in_data[159:152],  i_in_data[223:216]};
                        lane_data[4]  <= {i_in_data[39:32],  i_in_data[103:96],  i_in_data[167:160],  i_in_data[231:224]};
                        lane_data[5]  <= {i_in_data[47:40],  i_in_data[111:104], i_in_data[175:168],  i_in_data[239:232]};
                        lane_data[6]  <= {i_in_data[55:48],  i_in_data[119:112], i_in_data[183:176],  i_in_data[247:240]};
                        lane_data[7]  <= {i_in_data[63:56],  i_in_data[127:120], i_in_data[191:184],  i_in_data[255:248]};
                    end
                    else if (cycle_count == 1) begin
                        lane_data[0]  <= {i_in_data[263:256], i_in_data[327:320], i_in_data[391:384], i_in_data[455:448]};
                        lane_data[1]  <= {i_in_data[271:264], i_in_data[335:328], i_in_data[399:392], i_in_data[463:456]};
                        lane_data[2]  <= {i_in_data[279:272], i_in_data[343:336], i_in_data[407:400], i_in_data[471:464]};
                        lane_data[3]  <= {i_in_data[287:280], i_in_data[351:344], i_in_data[415:408], i_in_data[479:472]};
                        lane_data[4]  <= {i_in_data[295:288], i_in_data[359:352], i_in_data[423:416], i_in_data[487:480]};
                        lane_data[5]  <= {i_in_data[303:296], i_in_data[367:360], i_in_data[431:424], i_in_data[495:488]};
                        lane_data[6]  <= {i_in_data[311:304], i_in_data[375:368], i_in_data[439:432], i_in_data[503:496]};
                        lane_data[7]  <= {i_in_data[319:312], i_in_data[383:376], i_in_data[447:440], i_in_data[511:504]};
                    end

                    if (cycle_count == CLOCK_CYCLES_8 - 1) begin
                        cycle_count <= 0;
                        out_done <= 1 ;
                    end else begin
                        cycle_count <= cycle_count + 1;
                        out_done <= 0;
                    end
                end

                //====================================================
                // Lanes 8 → 15
                //====================================================
                DEGRADE_LANES_8_TO_15: begin
                    if (cycle_count == 0) begin
                        lane_data[8]  <= {i_in_data[7:0],    i_in_data[71:64],   i_in_data[135:128],  i_in_data[199:192]};
                        lane_data[9]  <= {i_in_data[15:8],   i_in_data[79:72],   i_in_data[143:136],  i_in_data[207:200]};
                        lane_data[10] <= {i_in_data[23:16],  i_in_data[87:80],   i_in_data[151:144],  i_in_data[215:208]};
                        lane_data[11] <= {i_in_data[31:24],  i_in_data[95:88],   i_in_data[159:152],  i_in_data[223:216]};
                        lane_data[12] <= {i_in_data[39:32],  i_in_data[103:96],  i_in_data[167:160],  i_in_data[231:224]};
                        lane_data[13] <= {i_in_data[47:40],  i_in_data[111:104], i_in_data[175:168],  i_in_data[239:232]};
                        lane_data[14] <= {i_in_data[55:48],  i_in_data[119:112], i_in_data[183:176],  i_in_data[247:240]};
                        lane_data[15] <= {i_in_data[63:56],  i_in_data[127:120], i_in_data[191:184],  i_in_data[255:248]};
                    end
                    else if (cycle_count == 1) begin
                        lane_data[8]  <= {i_in_data[263:256], i_in_data[327:320], i_in_data[391:384], i_in_data[455:448]};
                        lane_data[9]  <= {i_in_data[271:264], i_in_data[335:328], i_in_data[399:392], i_in_data[463:456]};
                        lane_data[10] <= {i_in_data[279:272], i_in_data[343:336], i_in_data[407:400], i_in_data[471:464]};
                        lane_data[11] <= {i_in_data[287:280], i_in_data[351:344], i_in_data[415:408], i_in_data[479:472]};
                        lane_data[12] <= {i_in_data[295:288], i_in_data[359:352], i_in_data[423:416], i_in_data[487:480]};
                        lane_data[13] <= {i_in_data[303:296], i_in_data[367:360], i_in_data[431:424], i_in_data[495:488]};
                        lane_data[14] <= {i_in_data[311:304], i_in_data[375:368], i_in_data[439:432], i_in_data[503:496]};
                        lane_data[15] <= {i_in_data[319:312], i_in_data[383:376], i_in_data[447:440], i_in_data[511:504]};
                    end

                    if (cycle_count == CLOCK_CYCLES_8 - 1) begin
                        cycle_count <= 0;
                        out_done <= 1; 
                    end else begin
                        cycle_count <= cycle_count + 1;
                        out_done <= 0;
                    end
                end

                //====================================================
                // Lanes 0 → 3
                //====================================================
                DEGRADE_LANES_0_TO_3: begin
                    if (cycle_count == 0) begin
                        lane_data[0] <= {i_in_data[7:0],   i_in_data[39:32],  i_in_data[71:64],  i_in_data[103:96]};
                        lane_data[1] <= {i_in_data[15:8],  i_in_data[47:40],  i_in_data[79:72],  i_in_data[111:104]};
                        lane_data[2] <= {i_in_data[23:16], i_in_data[55:48],  i_in_data[87:80],  i_in_data[119:112]};
                        lane_data[3] <= {i_in_data[31:24], i_in_data[63:56],  i_in_data[95:88],  i_in_data[127:120]};
                    end
                    else if (cycle_count == 1) begin
                        lane_data[0] <= {i_in_data[135:128], i_in_data[167:160], i_in_data[199:192], i_in_data[231:224]};
                        lane_data[1] <= {i_in_data[143:136], i_in_data[175:168], i_in_data[207:200], i_in_data[239:232]};
                        lane_data[2] <= {i_in_data[151:144], i_in_data[183:176], i_in_data[215:208], i_in_data[247:240]};
                        lane_data[3] <= {i_in_data[159:152], i_in_data[191:184], i_in_data[223:216], i_in_data[255:248]};
                    end
                    else if (cycle_count == 2) begin
                        lane_data[0] <= {i_in_data[263:256], i_in_data[295:288], i_in_data[327:320], i_in_data[359:352]};
                        lane_data[1] <= {i_in_data[271:264], i_in_data[303:296], i_in_data[335:328], i_in_data[367:360]};
                        lane_data[2] <= {i_in_data[279:272], i_in_data[311:304], i_in_data[343:336], i_in_data[375:368]};
                        lane_data[3] <= {i_in_data[287:280], i_in_data[319:312], i_in_data[351:344], i_in_data[383:376]};
                    end
                    else if (cycle_count == 3) begin
                        lane_data[0] <= {i_in_data[391:384], i_in_data[423:416], i_in_data[455:448], i_in_data[487:480]};
                        lane_data[1] <= {i_in_data[399:392], i_in_data[431:424], i_in_data[463:456], i_in_data[495:488]};
                        lane_data[2] <= {i_in_data[407:400], i_in_data[439:432], i_in_data[471:464], i_in_data[503:496]};
                        lane_data[3] <= {i_in_data[415:408], i_in_data[447:440], i_in_data[479:472], i_in_data[511:504]};
                    end

                    if (cycle_count == CLOCK_CYCLES_4 - 1) begin
                        cycle_count <= 0;
                        out_done <= 1;
                    end else begin
                        cycle_count <= cycle_count + 1;
                        out_done <= 0;
                    end
                end

                //====================================================
                // Lanes 4 → 7
                //====================================================
                DEGRADE_LANES_4_TO_7: begin
                    if (cycle_count == 0) begin
                        lane_data[4] <= {i_in_data[7:0],   i_in_data[39:32],  i_in_data[71:64],  i_in_data[103:96]};
                        lane_data[5] <= {i_in_data[15:8],  i_in_data[47:40],  i_in_data[79:72],  i_in_data[111:104]};
                        lane_data[6] <= {i_in_data[23:16], i_in_data[55:48],  i_in_data[87:80],  i_in_data[119:112]};
                        lane_data[7] <= {i_in_data[31:24], i_in_data[63:56],  i_in_data[95:88],  i_in_data[127:120]};
                    end
                    else if (cycle_count == 1) begin
                        lane_data[4] <= {i_in_data[135:128], i_in_data[167:160], i_in_data[199:192], i_in_data[231:224]};
                        lane_data[5] <= {i_in_data[143:136], i_in_data[175:168], i_in_data[207:200], i_in_data[239:232]};
                        lane_data[6] <= {i_in_data[151:144], i_in_data[183:176], i_in_data[215:208], i_in_data[247:240]};
                        lane_data[7] <= {i_in_data[159:152], i_in_data[191:184], i_in_data[223:216], i_in_data[255:248]};
                    end
                    else if (cycle_count == 2) begin
                        lane_data[4] <= {i_in_data[263:256], i_in_data[295:288], i_in_data[327:320], i_in_data[359:352]};
                        lane_data[5] <= {i_in_data[271:264], i_in_data[303:296], i_in_data[335:328], i_in_data[367:360]};
                        lane_data[6] <= {i_in_data[279:272], i_in_data[311:304], i_in_data[343:336], i_in_data[375:368]};
                        lane_data[7] <= {i_in_data[287:280], i_in_data[319:312], i_in_data[351:344], i_in_data[383:376]};
                    end
                    else if (cycle_count == 3) begin
                        lane_data[4] <= {i_in_data[391:384], i_in_data[423:416], i_in_data[455:448], i_in_data[487:480]};
                        lane_data[5] <= {i_in_data[399:392], i_in_data[431:424], i_in_data[463:456], i_in_data[495:488]};
                        lane_data[6] <= {i_in_data[407:400], i_in_data[439:432], i_in_data[471:464], i_in_data[503:496]};
                        lane_data[7] <= {i_in_data[415:408], i_in_data[447:440], i_in_data[479:472], i_in_data[511:504]};
                    end

                    if (cycle_count == CLOCK_CYCLES_4 - 1) begin
                        cycle_count <= 0;
                        out_done <= 1;
                    end else begin
                        cycle_count <= cycle_count + 1;
                        out_done <= 0;
                    end
                end

                default: begin
                    cycle_count <= 0;
                    out_done <= 0;
                end

                endcase
            end else begin
                out_done <= 0;
            end
        end
        else begin
            // IDLE state
            cycle_count     <= 0;
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
            out_done        <= 0;
        end
    end
"""

start_idx = -1
end_idx = -1

for i, line in enumerate(lines):
    if "always @(posedge i_clk or negedge i_rst_n) begin" in line:
        start_idx = i
        # We need to backtrack to include comments if any
        if i >= 3 and "//============================================================" in lines[i-3] and "// Sequential Logic" in lines[i-2]:
            start_idx = i-3
        break

# Find end_idx
open_count = 0
found_always = False
for i in range(start_idx, len(lines)):
    line = lines[i]
    if "begin" in line:
        # count 'begin's (crude but should work for well-formatted block)
        # Better: just look for the end of the always block.
        pass

# Since the block is contiguous until the `always @(*)`
for i in range(start_idx, len(lines)):
    if "always @(*)" in lines[i]:
        end_idx = i
        break

if end_idx != -1:
    # the end is just before the comment block of Output Assignment
    while "//" in lines[end_idx-1] or lines[end_idx-1].strip() == "":
        end_idx -= 1
else:
    print("Could not find end of sequential block")
    sys.exit(1)

new_lines = lines[:start_idx] + [new_block + "\n"] + lines[end_idx:]

with open(file_path, "w", encoding="utf-8") as f:
    f.writelines(new_lines)

print("Updated Mapper.sv successfully.")
