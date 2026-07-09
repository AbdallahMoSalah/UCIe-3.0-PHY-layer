#ifndef UCIE_CONFIG_H
#define UCIE_CONFIG_H

// =============================================================================
// UCIe link bring-up configuration.
//
//   Tweak the values here to change what Ucie_StartTraining() programs into the
//   sideband control registers. Nothing else needs editing — the driver
//   composes the register payloads from these defines using the bit-field
//   masks/shifts declared in ucie_driver.h.
//
//   Field encodings come straight from spec Table 9-9 (UCIe Link Control).
// =============================================================================

// ---- LINK_CTRL (0x10) negotiated targets ------------------------------------
// Target Link Width  : 0x1=x8  0x2=x16  0x3=x32  0x4=x64  0x5=x128  0x6=x256
#define CFG_TARGET_LINK_WIDTH    0x2          // x16

// Target Link Speed  : 0x0=4  0x1=8  0x2=12  0x3=16  0x4=24  0x5=32  0x6=48  0x7=64  (GT/s)
//   Kept low (8 GT/s) to match the slow FPGA lclk we actually run at.
#define CFG_TARGET_LINK_SPEED    0x1          // 8 GT/s

// ---- PHY_CONTROL (0x1004) ----------------------------------------------------
// Base payload for the bits we don't expose individually (Rx clk mode/phase,
// TARR, etc.). The x8-width bit below is OR'd in on top of this.
#define CFG_PHY_CONTROL_BASE     0x0000000000200060ULL   // -> REG_PHY_CONTROL (0x1004)

// Force x8 Width Mode in a UCIe-S x16 Module (PHY_CONTROL[8]): 1 = force x8, 0 = no.
#define CFG_PHY_FORCE_X8         0

// ---- TRAIN_SETUP3 (0x1030) lane mask -----------------------------------------
// 64-bit per-lane mask. A '1' in a bit position MASKS OUT (excludes) that lane
// from the pattern comparison; 0 = lane participates. Default 0 = no SW masking
// (the PHY still applies its width-based internal mask).
#define CFG_LANE_MASK            0x0000000000000000ULL

// ---- TRAIN_SETUP4 (0x1050) max error thresholds ------------------------------
// Per-lane comparison threshold  [15:4]  (12-bit, max 0xFFF)
#define CFG_MAX_ERR_THRESH_PER_LANE    0x00A          // 10
// Aggregate comparison threshold [31:16] (16-bit, max 0xFFFF)
#define CFG_MAX_ERR_THRESH_AGGREGATE   0x032          // 50

#endif // UCIE_CONFIG_H
