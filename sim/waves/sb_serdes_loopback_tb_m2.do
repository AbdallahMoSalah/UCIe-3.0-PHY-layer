onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /sb_serdes_loopback_tb_m2/serializer/clk_parallel
add wave -noupdate /sb_serdes_loopback_tb_m2/clk
add wave -noupdate /sb_serdes_loopback_tb_m2/rst_n
add wave -noupdate /sb_serdes_loopback_tb_m2/pmo_en
add wave -noupdate /sb_serdes_loopback_tb_m2/tx_parallel_data
add wave -noupdate /sb_serdes_loopback_tb_m2/tx_data_valid
add wave -noupdate /sb_serdes_loopback_tb_m2/tx_ready
add wave -noupdate /sb_serdes_loopback_tb_m2/TXDATASB
add wave -noupdate /sb_serdes_loopback_tb_m2/deserializer/RXDATASB
add wave -noupdate -color Blue /sb_serdes_loopback_tb_m2/TXCKSB
add wave -noupdate -color Blue /sb_serdes_loopback_tb_m2/deserializer/RXCKSB
add wave -noupdate /sb_serdes_loopback_tb_m2/send_packet/data
add wave -noupdate /sb_serdes_loopback_tb_m2/serializer/state
add wave -noupdate /sb_serdes_loopback_tb_m2/serializer/next_state
add wave -noupdate -expand -group ser -radix decimal /sb_serdes_loopback_tb_m2/serializer/bit_cnt
add wave -noupdate -expand -group ser /sb_serdes_loopback_tb_m2/serializer/shift_reg
add wave -noupdate -expand -group des -radix decimal /sb_serdes_loopback_tb_m2/deserializer/bit_cnt
add wave -noupdate -expand -group des /sb_serdes_loopback_tb_m2/deserializer/shift_reg
add wave -noupdate /sb_serdes_loopback_tb_m2/deserializer/packet_done
add wave -noupdate /sb_serdes_loopback_tb_m2/deserializer/next_shift
add wave -noupdate /sb_serdes_loopback_tb_m2/tx_data_exp
add wave -noupdate /sb_serdes_loopback_tb_m2/deserializer/rx_parallel_data_out
add wave -noupdate /sb_serdes_loopback_tb_m2/deserializer/rx_data_vld
add wave -noupdate /sb_serdes_loopback_tb_m2/pass
add wave -noupdate /sb_serdes_loopback_tb_m2/fail
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {254496 ps} 0}
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
WaveRestoreZoom {244 ns} {260 ns}
