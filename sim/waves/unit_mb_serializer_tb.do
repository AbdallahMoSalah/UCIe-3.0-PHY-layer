onerror {resume}
quietly WaveActivateNextPane {} 0

# Group: Clock & Reset
add wave -noupdate -divider {Clock & Reset}
add wave -noupdate -color {Cyan} /unit_mb_serializer_tb/pll_clk
add wave -noupdate -color {Light Blue} /unit_mb_serializer_tb/mb_clk
add wave -noupdate -color {Red} /unit_mb_serializer_tb/rst_n
add wave -noupdate -radix decimal /unit_mb_serializer_tb/pll_period_val
add wave -noupdate /unit_mb_serializer_tb/speed_sel

# Group: Testbench Stimulus
add wave -noupdate -divider {TB Stimulus}
add wave -noupdate /unit_mb_serializer_tb/ser_en
add wave -noupdate -radix hexadecimal /unit_mb_serializer_tb/in_data
add wave -noupdate -color {Yellow} /unit_mb_serializer_tb/ser_out

# Group: DUT Internal Control & CDC
add wave -noupdate -divider {DUT Internal Control & CDC}
add wave -noupdate /unit_mb_serializer_tb/DUT/load_toggle_mb
add wave -noupdate /unit_mb_serializer_tb/DUT/sync3_toggle
add wave -noupdate -color {Pink} /unit_mb_serializer_tb/DUT/rising_ser_en_pll

# Group: DUT Registers & Counter
add wave -noupdate -divider {DUT Registers & Counter}
add wave -noupdate -radix hexadecimal /unit_mb_serializer_tb/DUT/load_reg
add wave -noupdate -radix hexadecimal /unit_mb_serializer_tb/DUT/data_reg
add wave -noupdate -radix decimal /unit_mb_serializer_tb/DUT/ser_counter

# Group: DUT DDR Muxing & Retiming
add wave -noupdate -divider {DUT DDR Muxing & Retiming}
add wave -noupdate /unit_mb_serializer_tb/DUT/even_q
add wave -noupdate /unit_mb_serializer_tb/DUT/odd_q
add wave -noupdate /unit_mb_serializer_tb/DUT/high_reg
add wave -noupdate /unit_mb_serializer_tb/DUT/low_reg

TreeUpdate [SetDefaultTree]
configure wave -namecolwidth 250
configure wave -valuecolwidth 120
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
WaveRestoreZoom {0 ps} {1000000 ps}
