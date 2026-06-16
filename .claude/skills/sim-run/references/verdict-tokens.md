# Verdict tokens used by this repo's testbenches

`run_tb.sh` classifies a run by scanning the transcript for these, in priority order.

## Compile / elaboration failure (highest priority)
- `** Error` — QuestaSim vlog/vsim error prefix
- `Compilation Failed!` — emitted by `sim/scripts/run.do` on vlog failure
- `Error loading`, `cannot find`, `No such file`

## Hard fail
- `[WATCHDOG] timeout!` — TB self-timeout (e.g. `[WATCHDOG] timeout! scenarios_pass=%0d scenarios_fail=%0d`)
- `>>> FAIL : ...`, `>>> SOME TESTS FAILED <<<`, `>>> FAILURES DETECTED <<<`, `>>> ABORT (...)`
- `RESULT: FAIL`, `RESULT: FAIL (%0d mismatch(es))`
- `[FAIL] ...`, `<-- FAIL`
- nonzero counters: `scenarios_fail=N`, `pass=.. fail=N`, `N failed`, `N mismatch`

## Pass
- `>>> PASS : ...`, `>>> ALL TESTS PASSED`
- `RESULT: PASS`
- `[PASS] ...` lines with `failed 0` / `fail=0`
- `N/N` lockstep counts where numerator == denominator (e.g. `16/16 words descrambled in lockstep`)

## Notes
- Many TBs aggregate per-phase `[PASS]`/`[FAIL]` into a single `>>> PASS/FAIL` epilogue and a
  `SUMMARY :` line — prefer those for the headline.
- `run.do` runs `vsim -c` (console). In `-c` mode each line is prefixed with `# `; the script
  strips that before printing the summary.
- A run with no recognized token is reported `UNKNOWN`, not `PASS`.
