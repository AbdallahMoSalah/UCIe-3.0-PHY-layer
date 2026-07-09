#===========================================================================#
# PROJECT MACRO SIGNOFF
#===========================================================================#

#---------------------------------------------------------------------------#
# 1. ENVIRONMENT & VARIABLES
#---------------------------------------------------------------------------#
# External Delays (Outside the OpenFrame Chip)

set OUT_EXT_DELAY    22.0  

#---------------------------------------------------------------------------#
# 2. CLOCK DEFINITIONS
#---------------------------------------------------------------------------#
# The CLOCK_PERIOD variable below retrieves its value from the "CLOCK_PERIOD" 
# setting defined in the config.json file.

create_clock -name clk -period $::env(CLOCK_PERIOD) [get_ports {clk}]

set_propagated_clock [all_clocks]

#---------------------------------------------------------------------------#
# 3. CLOCK LATENCY & NON-IDEALITIES
#---------------------------------------------------------------------------#
# Clock Latencies based on Grid extremes (Min from Row0/Col0, Max from Row3/Col0)
set clk_max_latency 4.48
set clk_min_latency 0.32

set_clock_latency -source -max $clk_max_latency [get_clocks {clk}]
set_clock_latency -source -min $clk_min_latency [get_clocks {clk}]
puts "\[INFO\]: Setting clock latency range: $clk_min_latency : $clk_max_latency"

set_clock_uncertainty 0.1 [all_clocks]

#---------------------------------------------------------------------------#
# 4. DESIGN LIMITS & TIMING DERATES
#---------------------------------------------------------------------------#
set_max_transition    1.5 [current_design]
set_max_fanout        20  [current_design]

# Timing Derates (Accounting for PVT variations, 5%)
set_timing_derate -early 0.95
set_timing_derate -late  1.05

#---------------------------------------------------------------------------#
# 5. INPUT DELAYS
#---------------------------------------------------------------------------#
# Max Input: 4.0 (External) + 4.90 (Internal OpenFrame Muxes) = 8.90 ns
# Min Input: 4.0 (External) + 1.20 (Internal OpenFrame Fast Path) = 5.20 ns
set in_max_delay 8.90
set in_min_delay 5.20

puts "\[INFO\]: Setting max input delay to: $in_max_delay"
puts "\[INFO\]: Setting min input delay to: $in_min_delay"

set all_macro_inputs [get_ports {gpio_bot_in[*] gpio_rt_in[*] gpio_top_in[*]}]

set_input_delay -max $in_max_delay -clock [get_clocks {clk}] $all_macro_inputs
set_input_delay -min $in_min_delay -clock [get_clocks {clk}] $all_macro_inputs

#---------------------------------------------------------------------------#
# 6. OUTPUT DELAYS
#---------------------------------------------------------------------------#
# Max Output: OUT_EXT_DELAY + 9.71 (Internal OpenFrame Long Path)
# Min Output: OUT_EXT_DELAY + 2.72 (Internal OpenFrame Fast Path)
set out_max_delay [expr $OUT_EXT_DELAY + 9.71]
set out_min_delay [expr $OUT_EXT_DELAY + 2.72]

puts "\[INFO\]: Setting max output delay to: $out_max_delay"
puts "\[INFO\]: Setting min output delay to: $out_min_delay"

set all_macro_outputs [get_ports {gpio_bot_out[*] gpio_bot_oeb[*] gpio_bot_dm[*] \
                                  gpio_rt_out[*] gpio_rt_oeb[*] gpio_rt_dm[*] \
                                  gpio_top_out[*] gpio_top_oeb[*] gpio_top_dm[*]}]

set_output_delay -max $out_max_delay -clock [get_clocks {clk}] $all_macro_outputs
set_output_delay -min $out_min_delay -clock [get_clocks {clk}] $all_macro_outputs

#---------------------------------------------------------------------------#
# 7. INPUT TRANSITION & OUTPUT LOAD
#---------------------------------------------------------------------------#
# Data Inputs Transition (Based on max slew 0.287ns at macro boundary)
set_input_transition -max 0.35 $all_macro_inputs
set_input_transition -min 0.02 $all_macro_inputs

# Clock Input Transition (Based on max slew 0.618ns from ICG)
set_input_transition -max 0.65 [get_ports {clk}]
set_input_transition -min 0.25 [get_ports {clk}]

# Output Load
set_load 0.19 $all_macro_outputs

#---------------------------------------------------------------------------#
# 8. TIMING EXCEPTIONS (False Paths)
#---------------------------------------------------------------------------#
set_false_path -from [get_ports {reset_n por_n gpio_bot_in[0] gpio_bot_in[1] gpio_bot_in[2]}]
set_false_path -to [get_ports {gpio_bot_out[3] gpio_bot_out[4]}]
