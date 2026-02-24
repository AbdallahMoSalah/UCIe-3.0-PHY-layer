# UCIe PHY – Simulation Flow Guide

## 1. Overview

This project uses a robust, script-based simulation flow (no GUI projects) built around a single generic `run.do` file. All simulations are reproducible and fully CLI-driven.

**The flow supports:**

- Multiple configurations (via filelists)
    
- Debug mode (GUI + waves + coverage view)
    
- Batch run mode (fast execution)
    
- Coverage report generation (TXT & HTML)
    
- Controlled seed handling (Default, Fixed, Random)
    
- Per-testbench waveform files
    
- Per-testbench coverage configuration
    

## 2. Directory Structure

The simulation environment expects the following directory structure:

```
sim/
 ├── listfiles/        # Filelists per configuration (*.f files)
 ├── scripts/          # run.do (main entry point)
 ├── waves/            # Saved wave.do per testbench
 ├── coverage_cfg/     # Coverage exclusion configs per TB
 ├── coverage/         # Generated coverage reports & databases
 ├── logs/             # Seed logs (if random used)
 └── work/             # Compiled library (auto-generated & cleaned)
```

## 3. Quick Start & Main Entry Point

All simulations are launched using the `run.do` script. You must run it from the `sim/scripts` directory.

```
cd sim/scripts
vsim -do run.do
```

## 4. Supported Variables

You can override the default simulation behavior using Tcl variables passed via the command line:

|Variable|Description|Default Value|
|---|---|---|
|**`CONFIG`**|Filelist name (without `.f` extension)|`unit_rdi_packetizer`|
|**`TOP`**|Top-level Testbench module name|`RDI_Packetizer_tb`|
|**`MODE`**|Execution mode (`run`, `debug`, `report`)|`run`|
|**`SEED`**|Seed control (`default`, `random`, `<number>`)|`default`|
|**`REPORT_EXT`**|Coverage report format (`txt`, `html`)|`txt`|

_Example of overriding multiple variables:_

```
vsim -do "set MODE debug; set CONFIG my_config; set TOP my_tb; do run.do"
```

## 5. Simulation Modes

### `MODE = run` (Default)

Fast execution mode suitable for regressions.

- No GUI
    
- No coverage
    
- Auto exits upon completion
    

```
vsim -do run.do
```

### `MODE = debug`

Interactive debugging mode.

- Opens Questa GUI
    
- Coverage is visible inside the simulator
    
- Automatically loads the saved wave file (if it exists)
    
- Does NOT save coverage or generate reports
    
- Stays open after running
    

```
vsim -do "set MODE debug; do run.do"
```

### `MODE = report`

Batch mode for coverage collection.

- Runs without GUI
    
- Coverage enabled and collected
    
- Saves coverage database (`.ucdb`)
    
- Generates a text or HTML report (based on `REPORT_EXT`)
    
- Exits automatically
    

```
vsim -do "set MODE report; set REPORT_EXT html; do run.do"
```

_Generated output will be placed in:_ `sim/coverage/<TOP>/`

## 6. Seed Handling

- **`SEED = default`** (Default): Uses the Questa default seed. No `+SEED` argument is passed.
    
- **`SEED = random`**: Generates a random seed internally, passes it to vsim as `+SEED=<value>`, and logs the generated seed into `sim/logs/<TOP>.log`.
    
    ```
    vsim -do "set SEED random; do run.do"
    ```
    
- **`SEED = <number>`**: Uses a specific fixed seed for deterministic debugging.
    
    ```
    vsim -do "set SEED 12345; do run.do"
    ```
    

## 7. Waveform Flow

Wave files are stored per testbench in: `sim/waves/<TOP>.do`

**Behavior in Debug Mode:**

1. If the wave file exists → it is automatically loaded.
    
2. If it does not exist → full hierarchy is added automatically (`add wave -r sim:/*`).
    

**First-Time Setup:**

1. Run in debug mode: `vsim -do "set MODE debug; do run.do"`
    
2. Arrange signals manually in the GUI.
    
3. Save the waveform layout exactly as: `sim/waves/<TOP>.do`
    
4. Future debug runs will auto-load your layout.
    

## 8. Coverage Configuration

Coverage exclusion rules (e.g., reset toggles) are stored per testbench in: `sim/coverage_cfg/<TOP>.do`

**Example content:**

```
coverage exclude -du RDI_Packetizer -togglenode rst_n
```

- **Behavior:** Automatically loaded in `debug` and `report` modes. Ignored in `run` mode.
    
- _(Optional)_ Global exclusions can be placed in `sim/coverage_cfg/global.do` (if implemented).
    

## 9. Recommended Development Workflow

1. **Step 1 – Unit Development (Fast iteration):**
    
    ```
    vsim -do run.do
    ```
    
2. **Step 2 – Debug (Visual inspection):**
    
    ```
    vsim -do "set MODE debug; do run.do"
    ```
    
    _Inspect signals, adjust waveforms, and verify functionality._
    
3. **Step 3 – Coverage Review:**
    
    ```
    vsim -do "set MODE report; set REPORT_EXT html; do run.do"
    ```
    
    _Generate report, review toggle/branch/state coverage, and add specific exclusions in `coverage_cfg` if justified._
    
4. **Step 4 – Fix & Iterate:** Repeat until clean coverage is achieved.
    

## 10. Adding a New Testbench

To integrate a new Testbench into the flow:

1. Create a new filelist: `sim/listfiles/<config_name>.f`
    
2. Ensure the `TOP` variable matches your actual TB module name.
    
3. _(Optional)_ Add a wave layout: `sim/waves/<TOP>.do`
    
4. _(Optional)_ Add a coverage config: `sim/coverage_cfg/<TOP>.do`
    
5. **Run the new TB:**
    
    ```
    vsim -do "set CONFIG <config_name>; set TOP <tb_module>; do run.do"
    ```
    

## 11. Design Rules & Guidelines

- **Module Matching:** The `TOP` variable MUST exactly match the Testbench module name.
    
- **Naming Convention:** Wave file names and coverage config file names must match `TOP`.
    
- **No GUI Projects:** `.mpf` or tool-generated project files are NOT used and should not be committed to Git.
    

## 12. Industrial Notes

This flow is built with industrial best practices, supporting:

- Reproducible runs & CI-ready execution.
    
- Deterministic debugging via fixed seeds.
    
- Controlled random testing with proper logging.
    
- Clean and modular coverage management.
    

**Future Extensions:** Regression manager, Coverage merge support, and Seed sweep automation.