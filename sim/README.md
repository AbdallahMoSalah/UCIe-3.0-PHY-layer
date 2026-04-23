# UCIe PHY – Simulation Flow Documentation

---

# Adding a New Testbench – Complete Step-by-Step Guide

This section describes the complete workflow required to add and run a new testbench within the repository.

Follow these steps strictly to ensure consistency with the project structure.

---

## Step 1 – Create the Testbench File

Place the new testbench under the correct hierarchy inside `tb/`.

Choose the appropriate level:

* Unit-level test → `tb/unit/`
* Wrapper-level test → `tb/wrapper/`
* Integration test → `tb/integration/`
* Domain-level test → `tb/domain/`

Example (Unit Test for RDI DePacketizer):

```
tb/unit/sideband/rdi_depacketizer/RDI_DePacketizer_tb.sv
```

### Naming Rules

* File name must match module name.
* Testbench module must end with `_tb`.

Example:

```systemverilog
module RDI_DePacketizer_tb;
```

---

## Step 2 – Verify Dependencies

Ensure that:

* Required RTL files exist under `rtl/`
* Required packages are available
* There are no missing `include` dependencies

---

## Step 3 – Create Filelist Entry

Create a new filelist under:

```
sim/listfiles/
```

File naming convention:

```
<scope>_<block>.f
```

Example:

```
unit_rdi_depacketizer.f
```

### Filelist Rules

* Paths must be relative to project root
* Packages must be listed before modules
* Testbench must be last
* No duplicate entries

Example filelist:

```
rtl/SideBand/common/sb_pkg.sv
rtl/SideBand/Training_mgmt/RDI_DePacketizer.sv
tb/unit/sideband/rdi_depacketizer/RDI_DePacketizer_tb.sv
```

---

## Step 4 – (Optional) Create Wave Configuration

Run once in debug mode to generate signals.

Then save waveform configuration to:

```
sim/waves/RDI_DePacketizer_tb.do
```

Rules:

* Only include waveform display commands
* Do NOT include simulation control commands

---

## Step 5 – (Optional) Create Coverage Configuration

If exclusions are required, create:

```
sim/coverage_cfg/RDI_DePacketizer_tb.do
```

Example:

```
coverage exclude -du RDI_DePacketizer -togglenode rst_n
```

All exclusions must be justified.

---

## Step 6 – Run Using Makefile (Linux)

From project root:
**Example**
```bash
# On Linux 
/path/to/UCIe-3.0-PHY-layer/
# On Windows
D:\path\to\UCIe-3.0-PHY-layer\
```

```
make run CONFIG=unit_rdi_depacketizer TOP=RDI_DePacketizer_tb
```

Debug mode:

```
make debug CONFIG=unit_rdi_depacketizer TOP=RDI_DePacketizer_tb
```

Coverage report:

```
make report CONFIG=unit_rdi_depacketizer TOP=RDI_DePacketizer_tb
```

---

## Step 7 – Run Using PowerShell (Windows)

```
.\run_sim.ps1 -CONFIG unit_rdi_depacketizer -TOP RDI_DePacketizer_tb
```

Debug:

```
.\run_sim.ps1 -CONFIG unit_rdi_depacketizer -TOP RDI_DePacketizer_tb -MODE debug
```

Report:

```
.\run_sim.ps1 -CONFIG unit_rdi_depacketizer -TOP RDI_DePacketizer_tb -MODE report
```

---

## Step 8 – Validate Output

After successful run:

* Ensure no compilation errors
* Ensure no assertion failures
* Review coverage if applicable
* Verify waveform correctness in debug mode

---

## Step 9 – Clean Artifacts (Optional)

Linux:

```
make clean
```

Windows:

```
.\clean_sim.ps1
```

---

# Checklist Before Commit

Before pushing the new testbench:

* [ ] Filelist created
* [ ] Simulation passes
* [ ] No warnings
* [ ] Coverage reviewed
* [ ] Wave file cleaned (if committed)
* [ ] No tool-generated files added

---

This structured process ensures scalability, consistency, and industrial-level verification discipline.
