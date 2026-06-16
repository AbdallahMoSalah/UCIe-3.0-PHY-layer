---
name: sim-run
description: Run a single UCIe PHY testbench in QuestaSim and report a concise PASS/FAIL verdict. Use when asked to run/simulate a testbench, check that a TB passes, or run a CONFIG listfile. Auto-resolves the TOP module from the listfile when not given.
---

# sim-run

Run one testbench via the project Makefile and report a clean verdict instead of a raw QuestaSim transcript.

The run command is always `make run CONFIG=<listfile-basename> TOP=<tb-module>` from the **project root**. Listfiles live in `sim/listfiles/*.f`. `CONFIG` is the listfile basename (no `.f`); `TOP` is a module name, not a file.

## Instructions

### Step 1: Identify the CONFIG
Take the CONFIG (listfile) the user named. If they gave a `.f` path or a partial name, normalize to the basename. If it doesn't exist, the helper prints the closest matches in `sim/listfiles/` — show those and ask which one.

### Step 2: Run the helper
From the project root:

```
.claude/skills/sim-run/scripts/run_tb.sh <CONFIG> [TOP] [MODE]
```

- `TOP` optional — the helper resolves it from the listfile's `# Run ... TOP=` header, else by scanning the listed `.sv` files for a `*_tb*` module. Pass it explicitly only if resolution fails or you need a non-default top.
- `MODE` optional, default `run` (console). Use `debug` only if the user explicitly wants the GUI — it is interactive and will block.

### Step 3: Report the verdict
The helper prints a final `VERDICT:` line (`PASS`, `FAIL`, `COMPILE/ELAB ERROR`, or `UNKNOWN`) plus the summary/counter lines it found and, on failure, the failing excerpts. Relay:
- The verdict and the pass/fail counts.
- On FAIL/ERROR: the first failing assertion or compile error, as a clickable `file:line` when one is in the output.
- If `UNKNOWN`, the TB printed no recognized summary token — show the tail and say the verdict couldn't be auto-determined (don't claim PASS).

### Step 4: On a compile error
A `COMPILE/ELAB ERROR` is very often a stale listfile path (the recurring `rtl/common/*` vs `rtl/MainBand/tx/*` drift). Suggest running the `listfile-doctor` skill on this CONFIG before re-running.

## Notes
- Never run git write operations.
- Don't modify the Makefile, `sim/scripts/run.do`, or listfiles as part of a run — fixing a listfile is `listfile-doctor`'s job and should be a separate, surfaced action.
- The verdict vocabulary (`>>> PASS`/`>>> FAIL`, `[PASS]`/`[FAIL]`, `scenarios_pass=`, `N/N`, `[WATCHDOG] timeout`, `Compilation Failed`) is documented in `references/verdict-tokens.md`.
