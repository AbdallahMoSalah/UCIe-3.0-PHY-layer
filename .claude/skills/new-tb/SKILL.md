---
name: new-tb
description: Scaffold a new SystemVerilog testbench plus its matching QuestaSim listfile following this repo's conventions, so the TB is runnable and its verdict is auto-parseable. Use when asked to create/add a testbench, write a TB for a module, or set up a new CONFIG to simulate.
---

# new-tb

Generate a TB + listfile pair that drops straight into the `make run CONFIG=.. TOP=..` flow and reports verdicts the `sim-run`/`regression` skills can parse.

## Conventions this enforces
1. **Listfile is self-describing.** First lines are a comment block ending with the exact run command:
   `# Run : make run CONFIG=<config> TOP=<tb_module>`. This is what makes TOP auto-resolvable.
2. **Compile order:** RTL dependencies first (any `*_pkg.sv` before the modules that import it), DUT next, TB last.
3. **Canonical paths:** active MainBand RTL lives under `rtl/MainBand_RD/...` (and `rtl/MainBand/...` for the block-level dirs). Verify every path with the `listfile-doctor` skill before declaring done.
4. **Parseable verdict:** the TB prints `[PASS]`/`[FAIL]` per check, maintains `pass`/`fail` counters, has a `[WATCHDOG] timeout!` guard, and ends with a single `>>> PASS ...` / `>>> FAIL ...` epilogue. See `references/verdict-tokens.md` in the `sim-run` skill for the exact tokens.

## Instructions

### Step 1: Gather specifics
Confirm: DUT module name + its file path, the CONFIG name, the TB module name (convention: `<dut>_tb` or `unit_<thing>_tb`), and the DUT's port list (read the RTL — don't guess ports).

### Step 2: Copy and fill the templates
- TB: start from `assets/tb_template.sv`. Replace the `__TB__`, `__DUT__`, `__PORTS__`, and scenario placeholders. Instantiate the real DUT ports. Keep the counter/watchdog/epilogue scaffolding intact.
- Listfile: start from `assets/listfile_template.f`. Fill the header run line, list RTL deps in dependency order, DUT, then the TB file last.
- Place the TB under the matching `tb/` subtree (mirror existing `tb/unit/...` / `tb/integration/...` layout) and the listfile at `sim/listfiles/<config>.f`.

### Step 3: Validate before claiming it works
1. Run the `listfile-doctor` skill on the new CONFIG → must report `OK`.
2. Run the `sim-run` skill on it → report the real verdict. A scaffold that hasn't been run is not "done"; say so if you stop before running.

## Notes
- Match the surrounding TBs' style (clocking, scoreboard, quarter-clock RX sampling for serdes paths) — read a sibling TB in the same subtree first.
- Never run git write operations.
