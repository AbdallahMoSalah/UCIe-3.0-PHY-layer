# ============================================================
# UCIe PHY - UVM Advanced Simulation Script
# ============================================================

# ------------------------------------------------------------
# Assume execution from project root
# ------------------------------------------------------------

set project_root [pwd]
set sim_dir "$project_root/sim"

# Sanity check
if {![file exists "$sim_dir/listfiles"]} {
    puts "--------------------------------------------------"
    puts "ERROR: run_uvm.do must be launched from project root."
    puts "Example:"
    puts "  vsim -do sim/scripts/run_uvm.do"
    puts "--------------------------------------------------"
    quit -f
}

if {![info exists CONFIG]} {
    set CONFIG ucie_phy_uvm
}

if {![info exists TOP]} {
    set TOP ucie_tb_top
}

# -------------------------
# Defaults
# -------------------------
if {![info exists MODE]}         { set MODE run }
if {![info exists SEED]}         { set SEED default }
if {![info exists REPORT_EXT]}   { set REPORT_EXT txt }
if {![info exists SYNTH]}        { set SYNTH 0 }
if {![info exists TEST]}         { set TEST ucie_happy_path_test }
if {![info exists VERBOSITY]}    { set VERBOSITY UVM_LOW }

puts "--------------------------------------------------"
puts "PROJECT ROOT  = $project_root"
puts "CONFIG        = $CONFIG"
puts "TOP           = $TOP"
puts "MODE          = $MODE"
puts "SEED          = $SEED"
puts "UVM TEST      = $TEST"
puts "UVM VERBOSITY = $VERBOSITY"
puts "--------------------------------------------------"

# ------------------------------------------------------------
# Directories
# ------------------------------------------------------------

set work_dir         "$sim_dir/work"
set waves_dir        "$sim_dir/waves"
set coverage_dir     "$sim_dir/coverage"
set coverage_cfg_dir "$sim_dir/coverage_cfg"
set logs_dir         "$sim_dir/logs"

file mkdir $waves_dir
file mkdir $coverage_dir
file mkdir $coverage_cfg_dir
file mkdir $logs_dir

quit -sim

vlib $work_dir
vmap work $work_dir

# -------------------------
# Compile Flags
# -------------------------

if {$MODE eq "debug" || $MODE eq "report"} {
    set vlog_flags {-sv +cover -covercells}
} else {
    set vlog_flags {-sv}
}

if {$SYNTH == 0} {
    lappend vlog_flags +define+SIMULATION
}

set filelist_path "$sim_dir/listfiles/$CONFIG.f"

if {[catch {vlog {*}$vlog_flags -f $filelist_path} result]} {
    puts "Compilation Failed!"
    puts $result

    if {$MODE eq "ci" || $MODE eq "report" || $MODE eq "run"} {
        quit -f
    } else {
        return
    }
}

# -------------------------
# Seed Handling
# -------------------------

set seed_arg ""

if {$SEED eq "default"} {

    # Let Questa choose default seed

} elseif {$SEED eq "random"} {

    set real_seed [expr {int(rand()*1000000)}]
    set seed_arg "+SEED=$real_seed"

    set fp [open "$logs_dir/${TOP}.log" a]
    puts $fp "Generated SEED = $real_seed"
    close $fp

    puts "Generated SEED = $real_seed"

} else {

    set seed_arg "+SEED=$SEED"
}

# -------------------------
# Simulation Mode Handling
# -------------------------

set vsim_args [list]

if {$MODE eq "debug" || $MODE eq "report"} {
    lappend vsim_args -coverage
}

lappend vsim_args -voptargs=+acc
lappend vsim_args -wlf "$work_dir/$TOP.wlf"
lappend vsim_args work.$TOP

# UVM parameters
lappend vsim_args "+UVM_TESTNAME=$TEST"
lappend vsim_args "+UVM_VERBOSITY=$VERBOSITY"

if {$seed_arg ne ""} {
    lappend vsim_args $seed_arg
}

# -------------------------
# Launch Simulation
# -------------------------

if {[catch {
   vsim {*}$vsim_args
} result]} {
    puts "Simulation Launch Failed!"
    puts $result

    if {$MODE eq "ci" || $MODE eq "report" || $MODE eq "run"} {
        quit -f
    } else {
        return
    }
}

# ------------------------------------------------------------
# Debug Mode: Load Waveform
# ------------------------------------------------------------

if {$MODE eq "debug"} {

    set wave_file "$waves_dir/$TOP.do"

    if {[file exists $wave_file]} {
        puts "Loading wave file: $wave_file"
        do $wave_file
    } else {
        puts "No wave file found, loading full hierarchy"
        add wave -r sim:/*
    }
}

# ------------------------------------------------------------
# Load Coverage Configuration (if exists)
# ------------------------------------------------------------

if {$MODE eq "debug" || $MODE eq "report"} {

    set global_cov_cfg "$coverage_cfg_dir/global.do"
    if {[file exists $global_cov_cfg]} {
        puts "Loading global coverage config"
        do $global_cov_cfg
    }

    set tb_cov_cfg "$coverage_cfg_dir/$TOP.do"
    if {[file exists $tb_cov_cfg]} {
        puts "Loading TB coverage config"
        do $tb_cov_cfg
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

    set tb_cov_dir "$coverage_dir/$TOP"

    if {[file exists $tb_cov_dir]} {
        file delete -force $tb_cov_dir
    }

    file mkdir $tb_cov_dir
    
    if {$REPORT_EXT eq "txt"} {

        coverage save "$tb_cov_dir/$TOP.ucdb" -onexit

        quit -sim

        vcover report \
        "$tb_cov_dir/$TOP.ucdb" \
        -details \
        -all \
        -annotate \
        -output "$tb_cov_dir/coverage_rpt.txt"

    } elseif {$REPORT_EXT eq "html"} {

        coverage save "$tb_cov_dir/$TOP.ucdb" 

        vcover report \
        "$tb_cov_dir/$TOP.ucdb" \
        -details \
        -html \
        -annotate \
        -output "$tb_cov_dir"
    }

    puts "Coverage report generated in $tb_cov_dir"

    quit -f
}

if {$MODE eq "run" || $MODE eq "ci"} {

    quit -f
}
