---
name: listfile-doctor
description: Validate a QuestaSim listfile (sim/listfiles/*.f) so every compiled path exists, and suggest fixes for the common rtl/common-vs-rtl/MainBand/tx path drift. Use before running a TB that won't compile, when a sim hits a "file not found"/compile error, or to audit listfiles after moving RTL.
---

# listfile-doctor

Catch broken listfiles **before** wasting a QuestaSim invocation. The #1 compile failure in this repo is a listfile referencing a path that doesn't exist — classically `rtl/common/*` for files that actually live under `rtl/MainBand/tx/` (or a basename that moved during a refactor).

## Instructions

### Step 1: Run the checker
From the project root:

```
.claude/skills/listfile-doctor/scripts/check_listfile.sh <CONFIG|all>
```

- A single CONFIG (basename, with or without `.f`) checks one listfile.
- `all` audits every `sim/listfiles/*.f`.
- It ignores comment/blank lines and `+define`/`-sv`/`+incdir` style options, and checks each remaining path with `-f`.

### Step 2: Read the output
For each missing path it prints `MISSING: <path>` and, when a file with the same basename exists elsewhere in the repo, one or more `-> try: <path>` suggestions (from `git ls-files`, falling back to `find rtl`). A clean listfile prints `OK`.

### Step 3: Propose the fix, don't silently apply it
Listfiles are hand-curated and order-sensitive (packages before the modules that import them; TB last). When a `-> try:` suggestion is unambiguous (exactly one candidate, same basename), offer to repoint that line in place and keep its position. If there are multiple candidates or none, show them and ask which is correct — do not guess.

### Step 4: Re-validate
After editing, re-run the checker on that CONFIG to confirm `OK`, then hand back to `sim-run`.

## Notes
- Only edit listfiles, never the RTL, to make paths resolve — if the *file* is genuinely missing (no candidate anywhere), say so; the fix is to create RTL, not to doctor the listfile.
- Never run git write operations.
- Memory: many listfiles still point at not-yet-existent `rtl/common/*` paths; the established repoint is to `rtl/MainBand/tx/`.
