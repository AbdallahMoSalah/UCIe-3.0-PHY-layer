# UCIe PHY – FPGA fault-injection test software

A **copy** of `FPGA/src/` (the plain loopback bring-up software), modified to drive
the fault-injection bitstream and reproduce the error-injection scenarios of
`tb/integration/UCIe_PHY/UCIe_PHY_wrapper_tb.sv` on real hardware. The original
software is untouched (`FPGA/src/`, `vitis_ucie/app_component/src/`).

## Files
- `main.c` — scenario runner (table of TB-style faults + width/speed/force-x8).
- `ucie_driver.c/.h` — the original driver **reused verbatim**, plus added
  fault-injection helpers (`Ucie_Fi_*`), `Ucie_StartTrainingCustom`,
  `Ucie_LinkResetSoft`.
- `ucie_config.h` — unchanged from the original.
- `main_loopback_ref.c.txt` — the original loopback `main.c`, kept for reference
  (named `.txt` so it is not compiled as a second `main()`).

## Target hardware
Bitstream top = **`UCIe_FPGA_top_wrapper_fi`** (single die self-looped through
`ucie_loopback_fault_injector`). The fault taps are driven from **EMIO GPIO
bank 4** — the RDI control/status on bank 3 is unchanged:

| bank-4 output bit | injector control |
|---|---|
| `[15:0]` | `corrupt[15:0]` (per-lane stuck-at-0) |
| `[16]` | `reverse` (MB lane-order reversal) |
| `[17]` | `vld_err` (flip MB valid-frame strobe) |
| `[18]` | `block_sideband` (cut the sideband fold) |

> Block-design change required: widen the PS EMIO GPIO so bank 4 exists
> (EMIO width ≥ 51) and wire `emio_gpio_o[63:32][18:0]` to the FI wrapper's
> `{block_sideband, vld_err, reverse, corrupt[15:0]}`. See `ucie_driver.h`
> (`UCIE_FI_EMIO_BANK`, `FI_*` masks).

## Scenarios (`kScenarios[]` in `main.c`)
Each runs: soft link-reset → apply faults → program targets + start training →
bring up → check.

| Entry | Fault | Expected |
|---|---|---|
| SC1 | none | ACTIVE + data match |
| SC3 | force x8 | ACTIVE + data match |
| SC9 | speed 16 GT/s | ACTIVE + data match |
| SC4 | lane reversal | ACTIVE + data match |
| SC6 | corrupt lanes 8..15 | ACTIVE (degrade → x8) + data match |
| SC7 | corrupt lanes 0..7 | ACTIVE (degrade → x8) + data match |
| SC2 | block sideband | does **not** train (TRAINERROR) |
| SCx | corrupt all lanes | does **not** train |
| SCx | valid-strobe error | informational |

Toggle scenarios via the `enabled` bitmask in `main.c`.

## Build (Vitis)
The Vitis app globs every `*.c` in its source dir, so point an application
component at this folder (or copy these files over the app's `src/`, replacing
`main.c`). Do **not** keep two `main.c` in one build.

## Note on back-to-back scenarios
`Ucie_LinkResetSoft` drives RDI to RESET between scenarios but does **not** pulse
the PHY `rst_n` (not GPIO-mapped). For fully independent runs, add a PL-reset
GPIO/PS-reset and call it between scenarios (hook point noted in
`Ucie_LinkResetSoft`).
