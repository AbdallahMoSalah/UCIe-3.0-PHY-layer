onerror {resume}
quietly WaveActivateNextPane {} 0

add wave -noupdate -divider {System Clocks & Resets}
add wave -noupdate -group {System Control} -color White /SideBand_Top_tb/clk_main
add wave -noupdate -group {System Control} -color White /SideBand_Top_tb/rst_main_n
add wave -noupdate -group {System Control} -color White /SideBand_Top_tb/clk_sb
add wave -noupdate -group {System Control} -color White /SideBand_Top_tb/rst_sb_n
add wave -noupdate -group {System Control} -color White /SideBand_Top_tb/sb_pll_clock

add wave -noupdate -divider {DUT 0 (Sideband 0)}
add wave -noupdate -group {DUT 0 TB Controls} -color Yellow /SideBand_Top_tb/phy_in_reset\[0\]
add wave -noupdate -group {DUT 0 TB Controls} -color Yellow /SideBand_Top_tb/pmo_en\[0\]
add wave -noupdate -group {DUT 0 TB Controls} -color Yellow /SideBand_Top_tb/pattern_mode\[0\]
add wave -noupdate -group {DUT 0 TB Controls} -color Yellow /SideBand_Top_tb/start_pat_req\[0\]
add wave -noupdate -group {DUT 0 TB Controls} -color Yellow /SideBand_Top_tb/send_4_iter\[0\]
add wave -noupdate -group {DUT 0 Status} -color Green /SideBand_Top_tb/det_pat_rcvd\[0\]
add wave -noupdate -group {DUT 0 Status} -color Green /SideBand_Top_tb/four_iter_done\[0\]

add wave -noupdate -group {DUT 0 SerDes Links} -color Cyan /SideBand_Top_tb/TXCKSB\[0\]
add wave -noupdate -group {DUT 0 SerDes Links} -color Cyan /SideBand_Top_tb/TXDATASB\[0\]
add wave -noupdate -group {DUT 0 SerDes Links} -color Magenta /SideBand_Top_tb/RXCKSB\[0\]
add wave -noupdate -group {DUT 0 SerDes Links} -color Magenta /SideBand_Top_tb/RXDATASB\[0\]

add wave -noupdate -group {DUT 0 Link Controller States} /SideBand_Top_tb/dut_inst\[0\]/dut/u_link_controller/state
add wave -noupdate -group {DUT 0 Link Controller States} /SideBand_Top_tb/dut_inst\[0\]/dut/u_link_controller/next_state

add wave -noupdate -group {DUT 0 Training Mgmt States} /SideBand_Top_tb/dut_inst\[0\]/dut/u_training_mgmt/state
add wave -noupdate -group {DUT 0 Training Mgmt States} /SideBand_Top_tb/dut_inst\[0\]/dut/u_training_mgmt/next_state

add wave -noupdate -divider {DUT 1 (Sideband 1)}
add wave -noupdate -group {DUT 1 TB Controls} -color Yellow /SideBand_Top_tb/phy_in_reset\[1\]
add wave -noupdate -group {DUT 1 TB Controls} -color Yellow /SideBand_Top_tb/pmo_en\[1\]
add wave -noupdate -group {DUT 1 TB Controls} -color Yellow /SideBand_Top_tb/pattern_mode\[1\]
add wave -noupdate -group {DUT 1 TB Controls} -color Yellow /SideBand_Top_tb/start_pat_req\[1\]
add wave -noupdate -group {DUT 1 TB Controls} -color Yellow /SideBand_Top_tb/send_4_iter\[1\]
add wave -noupdate -group {DUT 1 Status} -color Green /SideBand_Top_tb/det_pat_rcvd\[1\]
add wave -noupdate -group {DUT 1 Status} -color Green /SideBand_Top_tb/four_iter_done\[1\]

add wave -noupdate -group {DUT 1 SerDes Links} -color Cyan /SideBand_Top_tb/TXCKSB\[1\]
add wave -noupdate -group {DUT 1 SerDes Links} -color Cyan /SideBand_Top_tb/TXDATASB\[1\]
add wave -noupdate -group {DUT 1 SerDes Links} -color Magenta /SideBand_Top_tb/RXCKSB\[1\]
add wave -noupdate -group {DUT 1 SerDes Links} -color Magenta /SideBand_Top_tb/RXDATASB\[1\]

add wave -noupdate -group {DUT 1 Link Controller States} /SideBand_Top_tb/dut_inst\[1\]/dut/u_link_controller/state
add wave -noupdate -group {DUT 1 Link Controller States} /SideBand_Top_tb/dut_inst\[1\]/dut/u_link_controller/next_state

add wave -noupdate -group {DUT 1 Training Mgmt States} /SideBand_Top_tb/dut_inst\[1\]/dut/u_training_mgmt/state
add wave -noupdate -group {DUT 1 Training Mgmt States} /SideBand_Top_tb/dut_inst\[1\]/dut/u_training_mgmt/next_state

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 350
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ps} {1000 ns}
