# UCIe PHY – Simulation Flow Documentation

This document describes the complete simulation workflow for the UCIe 3.0 PHY Digital Design project.

The simulation environment is fully script-based and does not rely on GUI project files.

All simulations are controlled through:

```
sim/scripts/run.do
```

The flow supports Linux and Windows environments.

---

# 1. Execution Requirement

All simulations MUST be launched from the project root directory.
**Example**
```bash
# On Linux 
/path/to/UCIe-3.0-PHY-layer/
# On Windows
D:\path\to\UCIe-3.0-PHY-layer\
```
	
Correct example:

Linux:

```
vsim -do sim/scripts/run.do
```

Incorrect example:

```
cd sim/scripts
vsim -do run.do
```

The script assumes project-root execution.

---

# 2. Simulation Variables

The following Tcl variables control simulation behavior:

|Variable|Required|Description|
|---|---|---|
|CONFIG|Yes|Filelist name (without .f)|
|TOP|Yes|Top-level testbench module|
|MODE|No|run / debug / report / ci|
|SEED|No|default / random /|
|REPORT_EXT|No|txt / html|

CONFIG and TOP are mandatory.

---

# 3. Simulation Modes

## MODE=run

- Console mode
    
- No coverage
    
- Fast execution
    
- Exits automatically
    

## MODE=debug

- GUI mode
    
- Coverage visible
    
- Loads wave file if available
    
- Does not exit automatically
    

## MODE=report

- Console mode
    
- Coverage enabled
    
- Generates coverage report
    
- Exits automatically
    

## MODE=ci

- Console mode
    
- Intended for automation pipelines
    
- Exits immediately on failure
    

---

# 4. Linux Usage (Makefile)

The project provides a Makefile wrapper.

## Basic Run

```
make run CONFIG=<filelist> TOP=<tb_module>
```

Example:

```
make run CONFIG=unit_rdi_packetizer TOP=RDI_Packetizer_tb
```

## Debug (GUI)

```
make debug CONFIG=<filelist> TOP=<tb_module>
```

## Coverage Report

```
make report CONFIG=<filelist> TOP=<tb_module>
```

Optional parameters:

```
make report CONFIG=unit_rdi_packetizer TOP=RDI_Packetizer_tb SEED=1234
```

## Clean

```
make clean
```

This removes:

- sim/work
    
- transcript
    
- vsim.wlf
    
- modelsim.ini
    

---

# 5. Linux Direct vsim Usage

Without Makefile:

```
vsim -c -do "set CONFIG unit_rdi_packetizer; set TOP RDI_Packetizer_tb; set MODE run; do sim/scripts/run.do"
```

Debug:

```
vsim -do "set CONFIG unit_rdi_packetizer; set TOP RDI_Packetizer_tb; set MODE debug; do sim/scripts/run.do"
```

Coverage report (TXT):

```
vsim -c -do "set CONFIG unit_rdi_packetizer; set TOP RDI_Packetizer_tb; set MODE report; set REPORT_EXT txt; do sim/scripts/run.do"
```

Coverage report (HTML):

```
vsim -c -do "set CONFIG unit_rdi_packetizer; set TOP RDI_Packetizer_tb; set MODE report; set REPORT_EXT html; do sim/scripts/run.do"
```

---

# 6. Windows Usage (PowerShell)

The repository includes:

- run_sim.ps1
    
- clean_sim.ps1
    

## Basic Run

```
.\run_sim.ps1 -CONFIG unit_rdi_packetizer -TOP RDI_Packetizer_tb
```

## Debug

```
.\run_sim.ps1 -CONFIG unit_rdi_packetizer -TOP RDI_Packetizer_tb -MODE debug
```

## Coverage Report

```
.\run_sim.ps1 -CONFIG unit_rdi_packetizer -TOP RDI_Packetizer_tb -MODE report
```

## Clean

```
.\clean_sim.ps1
```

---

# 7. Filelists

Filelists are stored in:

```
sim/listfiles/
```

Rules:

- Paths must be relative to project root
    
- Packages must be compiled before modules
    
- No duplicate entries
    

Example:

```
rtl/SideBand/common/sb_pkg.sv
rtl/SideBand/LinkMgmt/RDI_Packetizer.sv
tb/unit/sideband/rdi_packetizer/RDI_Packetizer_tb.sv
```

---

# 8. Wave Files

Wave configuration files:

```
sim/waves/<TOP>.do
```

Behavior:

- If file exists → automatically loaded in debug mode
    
- If not → full hierarchy added
    

---

# 9. Coverage Configuration

Per-testbench exclusions:

```
sim/coverage_cfg/<TOP>.do
```

Optional global exclusions:

```
sim/coverage_cfg/global.do
```

Coverage output directory:

```
sim/coverage/<TOP>/
```

---

# 10. Seed Handling

|SEED value|Behavior|
|---|---|
|default|Questa default seed|
|random|Auto-generated seed (logged)|
|number|Fixed seed|

Random seed logs stored in:

```
sim/logs/<TOP>.log
```

---

# 11. Common Errors

## Missing CONFIG or TOP

Both variables are mandatory.

## Running from wrong directory

Simulation must be launched from project root.

## Spaces in path

Spaces are supported, but avoid them when possible.

---

# 12. Design Philosophy

The simulation flow is designed to:

- Be reproducible
    
- Be deterministic
    
- Separate debug and batch behavior
    
- Support coverage-driven verification
    
- Be CI-ready
    
- Remain tool-project independent
    

---

For repository-level information, refer to:

```
README.md
```