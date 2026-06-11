onerror {resume}
quietly WaveActivateNextPane {} 0

# ── Clock & Reset ─────────────────────────────────────────────────────────────
add wave -noupdate -expand -group {Clock & Reset} \
    -color {Spring Green} /PHYRETRAIN_tb/clk
add wave -noupdate -expand -group {Clock & Reset} \
    -color {Spring Green} /PHYRETRAIN_tb/rst_n

# ── Control ───────────────────────────────────────────────────────────────────
add wave -noupdate -expand -group {Control} \
    -color Gold /PHYRETRAIN_tb/phyretrain_enable
add wave -noupdate -expand -group {Control} \
    -color Gold /PHYRETRAIN_tb/phyretrain_done
add wave -noupdate -expand -group {Control} \
    -color Orange /PHYRETRAIN_tb/phyretrain_error

# ── Register Inputs ───────────────────────────────────────────────────────────
add wave -noupdate -expand -group {Register Inputs} \
    -color Cyan /PHYRETRAIN_tb/rt_link_busy_status
add wave -noupdate -expand -group {Register Inputs} \
    -color Cyan -radix hex /PHYRETRAIN_tb/rt_test_ctrl
add wave -noupdate -expand -group {Register Inputs} \
    -color Orange /PHYRETRAIN_tb/global_error

# ── FSM State ─────────────────────────────────────────────────────────────────
add wave -noupdate -expand -group {FSM} \
    -color Magenta /PHYRETRAIN_tb/dut/current_state
add wave -noupdate -expand -group {FSM} \
    -color {Medium Violet Red} /PHYRETRAIN_tb/dut/next_state

# ── Internal Encoding ─────────────────────────────────────────────────────────
add wave -noupdate -expand -group {Encoding} \
    -color {Sky Blue} -radix binary /PHYRETRAIN_tb/dut/local_retrain_enc
add wave -noupdate -expand -group {Encoding} \
    -color Violet -radix binary /PHYRETRAIN_tb/dut/partner_enc_q
add wave -noupdate -expand -group {Encoding} \
    -color Yellow -radix binary /PHYRETRAIN_tb/dut/resolved_enc_q
add wave -noupdate -expand -group {Encoding} \
    -color {Light Salmon} -radix binary /PHYRETRAIN_tb/dut/partner_rsp_enc_q
add wave -noupdate -expand -group {Encoding} \
    -color {Green Yellow} -radix binary /PHYRETRAIN_tb/resolved_retrain_enc

# ── Handshake Flags ───────────────────────────────────────────────────────────
add wave -noupdate -expand -group {Handshake Flags} \
    -color {Cornflower Blue} /PHYRETRAIN_tb/dut/req_rcvd
add wave -noupdate -expand -group {Handshake Flags} \
    -color {Cornflower Blue} /PHYRETRAIN_tb/dut/rsp_rcvd

# ── SB TX ─────────────────────────────────────────────────────────────────────
add wave -noupdate -expand -group {SB TX} \
    -color Cyan /PHYRETRAIN_tb/tx_sb_msg_valid
add wave -noupdate -expand -group {SB TX} \
    -color Cyan /PHYRETRAIN_tb/tx_sb_msg
add wave -noupdate -expand -group {SB TX} \
    -color Cyan -radix binary /PHYRETRAIN_tb/tx_msginfo
add wave -noupdate -expand -group {SB TX} \
    -color {Spring Green} /PHYRETRAIN_tb/ltsm_rdy

# ── SB RX ─────────────────────────────────────────────────────────────────────
add wave -noupdate -expand -group {SB RX} \
    -color {Light Blue} /PHYRETRAIN_tb/rx_sb_msg_valid
add wave -noupdate -expand -group {SB RX} \
    -color {Light Blue} /PHYRETRAIN_tb/rx_sb_msg
add wave -noupdate -expand -group {SB RX} \
    -color {Light Blue} -radix binary /PHYRETRAIN_tb/rx_msginfo

TreeUpdate [SetDefaultTree]
quietly wave cursor active 1
configure wave -namecolwidth 280
configure wave -valuecolwidth 160
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
WaveRestoreZoom {0 ns} {3500 ns}
