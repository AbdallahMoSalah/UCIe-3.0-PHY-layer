# ===================================================
# Advanced Simulation Script
# ===================================================

# -------------------------
# Defaults
# -------------------------

if {![info exists CONFIG]}  { set CONFIG unit_rdi_packetizer }
if {![info exists TOP]}     { set TOP RDI_Packetizer_tb }
if {![info exists MODE]}    { set MODE run }
if {![info exists SEED]}    { set SEED default }
if {![info exists REPORT_EXT]}    { set REPORT_EXT txt }

puts "--------------------------------------"
puts "CONFIG = $CONFIG"
puts "TOP    = $TOP"
puts "MODE   = $MODE"
puts "SEED   = $SEED"
puts "--------------------------------------"

# -------------------------
# Work Directory
# -------------------------

if {[file exists ../work]} {
    vdel -lib work -all
    file delete -force ../work
}

vlib ../work
vmap work ../work

# -------------------------
# Compile Flags
# -------------------------

set vlog_flags "-sv"

if {$MODE eq "debug" || $MODE eq "report"} {
    set vlog_flags "$vlog_flags +cover -covercells"
}

if {[catch {eval vlog $vlog_flags -f ../listfiles/$CONFIG.f} result]} {
    puts "Compilation Failed!"
    puts $result
    quit -f
}

# -------------------------
# Seed Handling
# -------------------------

set seed_arg ""

if {$SEED eq "default"} {
    # Do nothing → let Questa choose default
} elseif {$SEED eq "random"} {
    set real_seed [expr {int(rand()*1000000)}]
    set seed_arg "+SEED=$real_seed"

    file mkdir ../logs
    set log_file "../logs/${TOP}.log"

    set fp [open $log_file a]
    puts $fp "Generated SEED = $real_seed"
    close $fp

    puts "Generated SEED = $real_seed"
} else {
    set seed_arg "+SEED=$SEED"
}

# -------------------------
# Simulation Mode Handling
# -------------------------

set vsim_flags "-voptargs=+acc"

if {$MODE eq "report"} {
    set vsim_flags "$vsim_flags -c -coverage"
}

if {$MODE eq "debug"} {
    set vsim_flags "$vsim_flags -coverage -gui"
}

# -------------------------
# Launch Simulation
# -------------------------

if {[catch {
    eval vsim $vsim_flags work.$TOP $seed_arg
} result]} {
    puts "Simulation Launch Failed!"
    puts $result
    quit -f
}

# -------------------------
# Wave Handling (Debug Mode Only)
# -------------------------

if {$MODE eq "debug"} {

    file mkdir ../waves
    set wave_file "../waves/$TOP.do"

    if {[file exists $wave_file]} {
        do $wave_file
    } else {
        add wave -r sim:/*
    }

}

# -------------------------
# Coverage Configuration
# -------------------------

if {$MODE eq "debug" || $MODE eq "report"} {

    set cov_cfg_file "../coverage_cfg/$TOP.do"

    if {[file exists $cov_cfg_file]} {
        puts "Loading coverage config: $cov_cfg_file"
        do $cov_cfg_file
    }

}

# -------------------------
# Run Simulation
# -------------------------

run -all

# -------------------------
# Coverage Report Mode
# -------------------------

if {$MODE eq "report"} {

    file mkdir ../coverage
    set cov_dir "../coverage/$TOP"

    if {[file exists $cov_dir]} {
        file delete -force $cov_dir
    }

    file mkdir $cov_dir

    coverage save "$cov_dir/$TOP.ucdb" -onexit

    if {$REPORT_EXT eq "txt"} {

        quit -sim

        vcover report \
        "$cov_dir/$TOP.ucdb" \
        -details \
        -all \
        -annotate \
        -output "$cov_dir/coverage_rpt.txt"
    } elseif {$REPORT_EXT eq "html"} {
        vcover report \
        "$cov_dir/$TOP.ucdb" \
        -details \
        -html \
        -annotate \
        -output "$cov_dir"
    }

    puts "Coverage report generated in $cov_dir"

    quit -f
}

# -------------------------
# Auto Quit for Run Mode
# -------------------------

if {$MODE eq "run"} {
    quit -f
}