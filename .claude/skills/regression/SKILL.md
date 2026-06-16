---
name: regression
description: Run a set of UCIe PHY testbenches and produce a pass/fail matrix, surfacing only the failures. Use when asked to run a regression, run all/several testbenches, run a whole subsystem's TBs, or sanity-check the suite after a change. Cross-platform replacement for run_sim.ps1 with aggregation.
---

# regression

Run many testbenches back-to-back and report a compact matrix, instead of eyeballing 129 separate transcripts. Builds on `sim-run`'s verdict logic.

## Instructions

### Step 1: Pick the selection
From the project root:

```
.claude/skills/regression/scripts/regression.sh <pattern|all> [MODE]
```

- `<pattern>` is a case-insensitive regex matched against listfile basenames, e.g. `mb_` , `integration_` , `^unit_l` , `lfsr`.
- `all` runs every `sim/listfiles/*.f`. **Warning:** that's 129 TBs and can take a long time — prefer a pattern unless the user truly wants the whole suite.
- Always confirm the scope with the user when they say "all" or the pattern matches a large set; show the count first (`regression.sh <pattern> --count` lists matches without running).

### Step 2: Pre-flight with the doctor (recommended)
Before a big run, validate the selected listfiles so compile failures don't masquerade as logic failures: run the `listfile-doctor` skill on `all` (or the pattern) and fix/flag broken ones first.

### Step 3: Run and report
The script runs each CONFIG through `sim-run`'s `run_tb.sh`, captures the `VERDICT:` line, and prints a matrix at the end plus a `PASS n / FAIL m / ERROR k / UNKNOWN u` tally. Relay:
- The tally and the matrix.
- For each non-PASS, the CONFIG name and its one-line reason (first failing excerpt / compile error).
- The path to the per-TB logs for anything the user wants to dig into.

### Step 4: Long runs
If the user wants the full suite, consider running the script with `run_in_background: true` (Bash) and reporting when it completes, rather than blocking. Mention the expected scale.

## Notes
- This is read-only with respect to the repo (it only compiles/simulates). Never edit RTL/listfiles here — route fixes through `listfile-doctor` or normal edits.
- Never run git write operations.
- Exit code is nonzero if any TB is not PASS, so it's usable as a CI gate.
