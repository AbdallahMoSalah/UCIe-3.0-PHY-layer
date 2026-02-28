# UCIe 3.0 PHY Layer – Digital Design & Verification

## 1. Project Overview

This repository contains the **Digital Design and Verification** of the UCIe 3.0 PHY Layer.

The scope of this project includes:

- Digital implementation of PHY building blocks
    
- Sideband path design and verification
    
- Mainband data path blocks
    
- LTSM and RDI-related state machines
    
- Unit-level, wrapper-level, and integration-level verification
    
- Coverage-driven verification flow
    
- Cross-platform simulation infrastructure (Linux & Windows)
    

The analog portion of the PHY is modeled only for simulation purposes and is not part of the synthesized RTL.

---

## 2. Repository Structure

```
.
├── rtl/                # RTL source code (Digital PHY)
├── tb/                 # Testbenches (unit / integration / domain / wrapper)
├── sim/                # Simulation infrastructure & flow
├── docs/               # Project documentation
├── Makefile            # Linux simulation wrapper
├── run_sim.ps1         # Windows simulation wrapper
├── clean_sim.ps1       # Windows cleanup script
└── README.md           # This file
```

---

## 3. RTL Hierarchy

The RTL is structured by functional domains.

```
rtl/
 ├── common/                # Shared packages and common definitions
 │
 ├── SideBand/              # Sideband digital path
 │    ├── common/           # Sideband-specific packages
 │    └── LinkMgmt/         # Packetizer / DePacketizer / Link blocks
 │
 ├── MainBand/              # Mainband data path
 │    ├── MAPPER/           # Data mapping logic
 │    └── DEMAPPER/         # Data demapping logic
 │
 └── MainSM/                # State machines
      ├── LTSM/
      ├── RDI SM/
      ├── RX RUNTIME CAL/
      └── TX RUNTIME CAL/
```

Each major functional block is designed to be verified independently before integration.

---

## 4. Testbench Hierarchy

Verification is layered to allow scalable growth:

```
tb/
 ├── unit/           # Unit-level verification (single module)
 ├── wrapper/        # Wrapper-level verification
 ├── integration/    # Multi-block integration tests
 └── domain/         # Higher-level domain verification
```

Unit tests are the foundation of the verification strategy.

Each testbench is expected to:

- Have a matching filelist in `sim/listfiles/`
    
- Have an optional wave configuration in `sim/waves/`
    
- Have an optional coverage configuration in `sim/coverage_cfg/`
    

---

## 5. Simulation Infrastructure

The simulation flow is fully script-based and does not rely on GUI project files.

Core components:

```
sim/
 ├── listfiles/        # Filelists per configuration (*.f)
 ├── scripts/          # run.do (main simulation engine)
 ├── waves/            # Saved waveform configurations per TB
 ├── coverage_cfg/     # Coverage exclusion rules per TB
 ├── coverage/         # Generated coverage databases & reports
 ├── logs/             # Random seed logs
 └── work/             # Compiled library (auto-generated)
```

The simulation engine is:

```
sim/scripts/run.do
```

Detailed simulation flow documentation is available in:

```
sim/README.md
```

---

## 6. Simulation Workflow

All simulations must be launched from the **project root directory**.
**Example**
```bash
# On Linux 
/path/to/UCIe-3.0-PHY-layer/
# On Windows
D:\path\to\UCIe-3.0-PHY-layer\
```

### Linux

```
make run   CONFIG=<filelist_name> TOP=<tb_module>
make debug CONFIG=<filelist_name> TOP=<tb_module>
make report CONFIG=<filelist_name> TOP=<tb_module>
make clean
```

### Windows (PowerShell)

```
.\run_sim.ps1 -CONFIG <filelist_name> -TOP <tb_module>
.\run_sim.ps1 -CONFIG <filelist_name> -TOP <tb_module> -MODE debug
.\run_sim.ps1 -CONFIG <filelist_name> -TOP <tb_module> -MODE report
.\clean_sim.ps1
```

Simulation behavior is controlled through:

- CONFIG (filelist)
    
- TOP (testbench module)
    
- MODE (run / debug / report / ci)
    
- SEED (default / random / fixed value)
    

---

## 7. Verification Modes

|Mode|GUI|Coverage|Report|Exit|
|---|---|---|---|---|
|run|No|No|No|Yes|
|debug|Yes|Visible|No|No|
|report|No|Yes|Yes|Yes|
|ci|No|Optional|No|Yes|

---

## 8. Coverage Strategy

- Coverage is enabled in `debug` and `report` modes.
    
- Per-testbench exclusions are stored in:
    

```
sim/coverage_cfg/<TOP>.do
```

- Optional global exclusions can be placed in:
    

```
sim/coverage_cfg/global.do
```

Coverage reports are generated in:

```
sim/coverage/<TOP>/
```

---

## 9. Design & Verification Principles

This repository follows several key principles:

- No GUI project files committed to Git
    
- All tool-generated files are ignored
    
- Reproducible simulation flow
    
- Separation between RTL and simulation artifacts
    
- Clear hierarchy between unit, wrapper, and integration tests
    
- Deterministic debugging via controlled seeds
    
- Coverage-driven verification
    

---

## 10. Contribution Guidelines (Planned)

A separate document will define:

- Naming conventions
    
- Filelist rules
    
- Testbench structure rules
    
- Coverage exclusion justification policy
    
- Branching strategy
    

This document will be added as:

```
CONTRIBUTING.md
```

---

## 11. Documentation Roadmap

Additional documentation files may be added under:

```
docs/
```

Planned documents:

- Architecture Overview
    
- PHY Block-Level Description
    
- Verification Strategy Document
    
- Integration Plan
    

---

## 12. Project Status

This repository is under active development.

Directory structure and integration flow are continuously evolving as blocks are completed and verified.

---

For detailed simulation usage, refer to:

```
sim/README.md
```
