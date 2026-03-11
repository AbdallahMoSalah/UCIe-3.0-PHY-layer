onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /sb_serdes_loopback_tb/clk
add wave -noupdate /sb_serdes_loopback_tb/rst_n
add wave -noupdate /sb_serdes_loopback_tb/pmo_en
add wave -noupdate /sb_serdes_loopback_tb/tx_parallel_data
add wave -noupdate /sb_serdes_loopback_tb/tx_data_valid
add wave -noupdate /sb_serdes_loopback_tb/tx_ready
add wave -noupdate /sb_serdes_loopback_tb/tx_serial_out
add wave -noupdate /sb_serdes_loopback_tb/deserializer/rx_serial_in
add wave -noupdate -color Blue /sb_serdes_loopback_tb/TXCKSB
add wave -noupdate -color Blue /sb_serdes_loopback_tb/deserializer/RXCKSB
add wave -noupdate /sb_serdes_loopback_tb/rx_parallel_data
add wave -noupdate /sb_serdes_loopback_tb/rx_data_valid
add wave -noupdate /sb_serdes_loopback_tb/send_packet/data
add wave -noupdate /sb_serdes_loopback_tb/serializer/state
add wave -noupdate /sb_serdes_loopback_tb/serializer/next_state
add wave -noupdate -expand -group ser -radix decimal /sb_serdes_loopback_tb/serializer/bit_cnt
add wave -noupdate -expand -group ser /sb_serdes_loopback_tb/serializer/shift_reg
add wave -noupdate -expand -group des -radix decimal /sb_serdes_loopback_tb/deserializer/bit_cnt
add wave -noupdate -expand -group des /sb_serdes_loopback_tb/deserializer/shift_reg
add wave -noupdate /sb_serdes_loopback_tb/deserializer/packet_data
add wave -noupdate /sb_serdes_loopback_tb/deserializer/packet_done
add wave -noupdate /sb_serdes_loopback_tb/deserializer/next_shift
add wave -noupdate /sb_serdes_loopback_tb/pass
add wave -noupdate /sb_serdes_loopback_tb/fail
add wave -noupdate /sb_serdes_loopback_tb/deserializer/SVA_des/cover__p_data_stable
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {696 ns} 0}
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
WaveRestoreZoom {679 ns} {711 ns}
