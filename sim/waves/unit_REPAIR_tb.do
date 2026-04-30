onerror {resume}
quietly WaveActivateNextPane {} 0

# ── Clock & Reset ─────────────────────────────────────────────────────────────
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} /unit_REPAIR_tb/rst_n
add wave -noupdate -expand -group {Clock & Reset} -color {Spring Green} /unit_REPAIR_tb/lclk

# ── Control ───────────────────────────────────────────────────────────────────
add wave -noupdate -expand -group {Control} -color Gold      /unit_REPAIR_tb/intf/repair_en
add wave -noupdate -expand -group {Control} -color Gold      /unit_REPAIR_tb/intf/repair_done
add wave -noupdate -expand -group {Control} -color Gold      /unit_REPAIR_tb/intf/txselfcal_req

# ── FSM State ─────────────────────────────────────────────────────────────────
add wave -noupdate -expand -group {FSM State} -color Magenta  /unit_REPAIR_tb/current_state

# ── Data Path (Lane Map) ──────────────────────────────────────────────────────
add wave -noupdate -expand -group {Data Path} -color Violet   /unit_REPAIR_tb/unit_REPAIR_inst/local_tx_lane_map_code
add wave -noupdate -expand -group {Data Path} -color Violet   /unit_REPAIR_tb/unit_REPAIR_inst/local_rx_lane_map_code
add wave -noupdate -expand -group {Data Path} -color Violet   -radix hex /unit_REPAIR_tb/intf/linkspeed_success_lanes
add wave -noupdate -expand -group {Data Path} -color Violet   /unit_REPAIR_tb/intf/rf_cap_SPMW
add wave -noupdate -expand -group {Data Path} -color Violet   /unit_REPAIR_tb/intf/rf_ctrl_target_link_width
add wave -noupdate -expand -group {Data Path} -color Violet   /unit_REPAIR_tb/intf/param_UCIe_S_x8
add wave -noupdate -expand -group {Data Path} -color Violet   -radix hex /unit_REPAIR_tb/intf/mb_tx_data_lane_mask
add wave -noupdate -expand -group {Data Path} -color Violet   -radix hex /unit_REPAIR_tb/intf/mb_rx_data_lane_mask

# ── SB Messages ───────────────────────────────────────────────────────────────
add wave -noupdate -expand -group {SB Messages} -color Cyan         /unit_REPAIR_tb/intf/tx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color Cyan         /unit_REPAIR_tb/intf/tx_sb_msg_valid
add wave -noupdate -expand -group {SB Messages} -color Cyan         -radix hex /unit_REPAIR_tb/intf/tx_msginfo
add wave -noupdate -expand -group {SB Messages} -color {Spring Green} /unit_REPAIR_tb/intf/rx_sb_msg
add wave -noupdate -expand -group {SB Messages} -color {Spring Green} /unit_REPAIR_tb/intf/rx_sb_msg_valid
add wave -noupdate -expand -group {SB Messages} -color {Spring Green} -radix hex /unit_REPAIR_tb/intf/rx_msginfo

# ── Errors & Alerts ───────────────────────────────────────────────────────────
add wave -noupdate -expand -group {Errors & Alerts} -color Orange /unit_REPAIR_tb/intf/timeout_8ms_occured
add wave -noupdate -expand -group {Errors & Alerts} -color Orange /unit_REPAIR_tb/intf/trainerror_req

TreeUpdate [SetDefaultTree]
quietly wave cursor active 2
configure wave -namecolwidth 380
configure wave -valuecolwidth 200
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
WaveRestoreZoom {0 ps} {100000000 ps}
