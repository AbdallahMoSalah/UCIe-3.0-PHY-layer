onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /Link_Arbiter_tb/clk
add wave -noupdate -expand -group Link_input /Link_Arbiter_tb/LINK_msg
add wave -noupdate -expand -group Link_input -color Blue /Link_Arbiter_tb/LINK_vld
add wave -noupdate -expand -group mapper_ready -color Yellow /Link_Arbiter_tb/mapper_ready
add wave -noupdate -expand -group adapter_input /Link_Arbiter_tb/adapter_msg
add wave -noupdate -expand -group adapter_input /Link_Arbiter_tb/adapter_rd_en
add wave -noupdate -expand -group {whos ready} /Link_Arbiter_tb/adapter_not_empty
add wave -noupdate -expand -group {whos ready} -color Blue /Link_Arbiter_tb/LINK_ready
add wave -noupdate -expand -group {what send} /Link_Arbiter_tb/msg_word_send
add wave -noupdate -expand -group {what send} -color Yellow /Link_Arbiter_tb/valid_s
add wave -noupdate /Link_Arbiter_tb/pass_count
add wave -noupdate /Link_Arbiter_tb/fail_count
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {28753 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
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
WaveRestoreZoom {0 ps} {55360 ps}
