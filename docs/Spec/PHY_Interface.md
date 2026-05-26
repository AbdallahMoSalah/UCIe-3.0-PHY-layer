**RDI Signal Assignment to PHY Containers**

---

**GLOBAL**

|Signal|Direction|Description|
|---|---|---|
|lclk|—|RDI operating clock|

---

**MainBand (MB_TX / MB_RX)**

Adapter → PHY:

|Signal|Description|
|---|---|
|lp_irdy|Adapter has data ready to send|
|lp_valid|Data on lp_data is valid|
|lp_data[NBYTES-1:0][7:0]|Transmit data bytes|
|lp_retimer_crd|Credit return for Retimer RX buffers (Retimer only)|

PHY → Adapter:

|Signal|Description|
|---|---|
|pl_trdy|PHY ready to accept data|
|pl_valid|Data on pl_data is valid|
|pl_data[NBYTES-1:0][7:0]|Receive data bytes|
|pl_retimer_crd|Credit return from Retimer to Adapter (Retimer only)|

---

**MainSM (RDI_SM / LTSM)**

Adapter → PHY:

|Signal|Description|
|---|---|
|lp_state_req[3:0]|State change request (NOP/Active/L1/L2/LinkReset/Retrain/Disabled)|
|lp_linkerror|Fatal error — force PHY to LinkError immediately|
|lp_stallack|Ack to PHY that Adapter is stalled at Flit boundary|
|lp_clk_ack|Ack that Adapter clocks ungated (response to pl_clk_req)|
|lp_wake_req|Request PHY to ungate its clocks|

PHY → Adapter:

|Signal|Description|
|---|---|
|pl_state_sts[3:0]|Current RDI state (Reset/Active/PMNAK/L1/L2/LinkReset/LinkError/Retrain/Disabled)|
|pl_inband_pres|Link training done; ready for RDI Active transition|
|pl_stallreq|Request Adapter to stall at Flit boundary|
|pl_clk_req|Request Adapter to ungate its clocks|
|pl_wake_ack|Ack that PHY clocks ungated (response to lp_wake_req)|
|pl_speedmode[2:0]|Current operating link speed|
|pl_max_speedmode|Negotiated max data rate (0: ≤32 GT/s, 1: >32 GT/s)|
|pl_lnk_cfg[2:0]|Current operating link width (x4/x8/x16/x32/x64)|
|pl_phyinrecenter|PHY is in training or retraining|
|pl_error|Recoverable framing error detected (pulse, Active state only)|
|pl_cerror|Correctable error detected (pulse, any state)|
|pl_nferror|Non-fatal error detected (pulse, any state)|
|pl_trainerror|Fatal training error — forces LinkError (level signal)|

---

**SideBand (RDI_Control / Reg_Access)**

Adapter → PHY:

|Signal|Description|
|---|---|
|lp_cfg[NC-1:0]|Sideband config bus data (Adapter→PHY); NC = 8, 16, or 32|
|lp_cfg_vld|lp_cfg has valid data|
|lp_cfg_crd|Credit return for sideband packets (Adapter→PHY)|

PHY → Adapter:

| Signal         | Description                                               |
| -------------- | --------------------------------------------------------- |
| pl_cfg[NC-1:0] | Sideband config bus data (PHY→Adapter); NC = 8, 16, or 32 |
| pl_cfg_vld     | pl_cfg has valid data                                     |
| pl_cfg_crd     | Credit return for sideband packets (PHY→Adapter)          |

### Complete PHY Partner Interface Summary

| Interface              | Side          | Signals                                  | Count  |
| ---------------------- | ------------- | ---------------------------------------- | ------ |
| Mainband TX            | PHY → Partner | TXDATA[15:0], TXVLD, TXTRK, TXCKP, TXCKN | 20     |
| Mainband RX            | Partner → PHY | RXDATA[15:0], RXVLD, RXTRK, RXCKP, RXCKN | 20     |
| Sideband TX            | PHY → Partner | TXDATASB, TXCKSB                         | 2      |
| Sideband RX            | Partner → PHY | RXDATASB, RXCKSB                         | 2      |
| **Total data signals** |               |                                          | **44** |
