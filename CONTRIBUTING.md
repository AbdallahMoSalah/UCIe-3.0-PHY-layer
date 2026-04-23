# CONTRIBUTING Guidelines

## 1. Purpose

This document defines the contribution rules and development standards for the **UCIe 3.0 PHY – Digital Design & Verification** repository.

The goal is to ensure:

* Consistent coding style
* Clean simulation flow
* Scalable verification methodology
* Reproducible results
* Maintainable project structure

All contributors are expected to follow these guidelines.

---

## 2. Repository Location

This file must be located at the project root:

```
CONTRIBUTING.md
```

It applies to all directories within the repository.

---

## 3. Branching Strategy

### Main Branches

* `main` → Stable milestone releases
* `dev`  → Active integration branch

### Feature Development

Each new feature must be developed in a dedicated branch:

```
feature/<block_name>
```

Example:

```
feature/rdi_packetizer
```

Rules:

* No direct commits to `main`
* Pull requests required before merging to `dev`
* All simulations must pass before merge

---

## 4. RTL Contribution Rules

### 4.1 File Naming

* Module name must match file name
* One primary module per file
* Use clear, descriptive names

Example:

```
RDI_Packetizer.sv
```

### 4.2 Packages

* Common packages → `rtl/common/`
* Domain-specific packages → local `common/` directory inside that domain
* Avoid circular package dependencies

### 4.3 Coding Style

* Use `logic` instead of `wire/reg`
* Use `always_ff`, `always_comb`
* Explicit reset behavior
* No implicit latches
* No blocking assignments in sequential logic

### 4.4 Reset Policy

* Synchronous reset preferred unless otherwise required
* Active-low naming convention: `rst_n`

---

## 5. Testbench Contribution Rules

### 5.1 Location

Testbenches must be placed under:

```
tb/unit/
tb/wrapper/
tb/integration/
tb/domain/
```

### 5.2 Naming

Testbench name must match:

```
<TOP>_tb.sv
```

Example:

```
RDI_Packetizer_tb.sv
```

### 5.3 Filelist Requirement

Every testbench must have a corresponding filelist:

```
sim/listfiles/<config_name>.f
```

The filelist must:

* Use paths relative to project root
* Include required packages before modules
* Avoid duplicate compilation entries

---

## 6. Simulation Flow Rules

### 6.1 Execution

Simulation must always be launched from project root.

Linux:

```
make run CONFIG=<config> TOP=<tb>
```

Windows:

```
.\run_sim.ps1 -CONFIG <config> -TOP <tb>
```

### 6.2 No GUI Projects

* Do not commit Questa project files
* Do not commit transcript or work directories
* Do not commit coverage databases

---

## 7. Coverage Policy

### 7.1 Coverage Requirements

* New blocks must reach acceptable functional coverage
* Toggle and branch coverage must be reviewed

### 7.2 Coverage Exclusions

Exclusions must:

* Be justified
* Be documented
* Be placed in:

```
sim/coverage_cfg/<TOP>.do
```

No unjustified exclusions are allowed.

---

## 8. Wave Configuration

Waveform configuration files:

```
sim/waves/<TOP>.do
```

Rules:

* Must only contain signal additions and formatting
* Must not contain simulation control commands

---

## 9. Commit Message Format

Use structured commit messages:

```
[BLOCK] Short description
```

Examples:

```
[RDI] Fix packet header alignment
[SB] Add timeout handling in Training_mgmt
[TB] Add directed reset test
```

---

## 10. Integration Rules

Before merging to `dev`:

* Unit tests must pass
* No compilation warnings
* No failing assertions
* Coverage must be reviewed

---

## 11. Code Review Checklist

Reviewers should verify:

* Proper reset handling
* No combinational loops
* Clean interface definition
* Correct package usage
* No hardcoded delays in synthesizable RTL
* Assertions added where appropriate

---

## 12. Documentation Expectations

New blocks must include:

* Short architectural description
* Interface definition
* Expected behavior description

Documentation should be added under:

```
docs/
```

---

## 13. Long-Term Goals

The repository is structured to support:

* Regression automation
* Coverage merging
* CI pipeline integration
* Transition to advanced verification methodology (e.g., UVM)

All contributions should align with these goals.

---

## 14. Final Note

This project is structured to resemble an industrial verification environment.

Consistency, reproducibility, and clarity are more important than speed.

Follow the structure. Respect the hierarchy. Keep the repository clean.
