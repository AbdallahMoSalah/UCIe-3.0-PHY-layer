onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /unit_clk_handshake_tb/lclk
add wave -noupdate /unit_clk_handshake_tb/clk_handshake_strt
add wave -noupdate /unit_clk_handshake_tb/lp_clk_ack
add wave -noupdate /unit_clk_handshake_tb/pl_clk_req
add wave -noupdate /unit_clk_handshake_tb/clk_handshake_done
add wave -noupdate /unit_clk_handshake_tb/exp_pl_clk_req
add wave -noupdate /unit_clk_handshake_tb/exp_clk_handshake_done
add wave -noupdate /unit_clk_handshake_tb/exp_state
add wave -noupdate /unit_clk_handshake_tb/err_count
add wave -noupdate /unit_clk_handshake_tb/drive_inputs/strt
add wave -noupdate /unit_clk_handshake_tb/drive_inputs/ack
add wave -noupdate /unit_clk_handshake_tb/dut/lp_clk_ack
add wave -noupdate /unit_clk_handshake_tb/dut/clk_handshake_strt
add wave -noupdate /unit_clk_handshake_tb/dut/lclk
add wave -noupdate /unit_clk_handshake_tb/dut/pl_clk_req
add wave -noupdate /unit_clk_handshake_tb/dut/clk_handshake_done
add wave -noupdate /unit_clk_handshake_tb/dut/CLK_cs
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {12437 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 190
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
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {223684 ps}
