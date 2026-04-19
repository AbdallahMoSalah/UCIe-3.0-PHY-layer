module RDI_control (
   // Adapter/RDI interface
   input  logic [32:0]   lp_cfg,
   input  logic          lp_cfg_vld,
   
   output logic          pl_cfg_crd,
   input  logic          lp_cfg_crd,

   output logic [32:0]   pl_cfg,
   output logic          pl_cfg_vld,
   
   // Link/RDI interface
   input  logic [32:0]   Adapter_msg_rcvd,
   input  logic          Adapter_vld_rcvd,
   
   output logic [127:0]  Adapter_msg_send,
   output logic          Adapter_vld_send,
   input  logic          Adapter_ready,

   // Reg/RDI interface
   input  logic [32:0]   completion_msg,
   input  logic          completion_vld,
   output logic          completion_ready,

   input  logic [32:0]   reg_msg,
   input  logic          reg_vld,
   output logic          reg_ready,

   // RDISM interface 
   output logic          traffic_req,
   input  logic          traffic_ready,
   input  logic          phy_in_reset
   
);

// Down Stream

rdi_aggregator u_rdi_aggregator(
    .clk               ( clk               ),
    .rst_n             ( rst_n             ),
    .lp_cfg            ( lp_cfg            ),
    .lp_cfg_vld        ( lp_cfg_vld        ),
    .lp_msg            ( lp_msg            ),
    .lp_msg_vld        ( lp_msg_vld        )
);

// Up Stream

rdi_de_aggregator u_rdi_de_aggregator(
    .clk               ( clk               ),
    .rst_n             ( rst_n             ),
    .pl_msg            ( pl_msg            ),
    .pl_msg_vld        ( pl_msg_vld        ),
    .pl_msg_ready      ( pl_msg_ready      ),
    .traffic_req       ( traffic_req       ),
    .traffic_ready     ( traffic_ready     ),
    .pl_cfg            ( pl_cfg            ),
    .pl_cfg_vld        ( pl_cfg_vld        )
);


    
sb_priority_arbiter #(
    .DATA_WIDTH(128)
) u_fifo_arbiter (
    .hp_msg            ( Link_msg_send     ),
    .hp_vld            ( Link_vld_send     ),
    .hp_ready          ( Link_ready        ),
    .lp_msg            ( Adapter_msg_send  ),
    .lp_vld            ( Adapter_vld_send  ),
    .lp_ready          ( Adapter_ready     ),
    .out_msg           ( pl_msg            ),
    .out_vld           ( pl_msg_vld        ),
    .out_ready         ( pl_msg_ready      )
);

fifo #(
    .DATA_WIDTH (128),
    .ADDR_WIDTH (4),
    .ASYNC      (0)
) u_fifo_RDI_ctrl_up_req (
    // Write port (Adapter → FIFO)
    .W_CLK      (clk),
    .WRST_N     (rst_n),
    .WINC       (Adapter_vld_send),     // push when Adapter has valid data
    .WR_DATA    (Adapter_msg_send),
    .WFULL      (),                     // unused — use WREADY for backpressure
    .WREADY     (Adapter_ready),        // ~WFULL → tell Adapter it can send

    // Read port (FIFO → Link/downstream)
    .R_CLK      (clk),
    .RRST_N     (rst_n),
    .RINC       (Adapter_vld_rcvd),     // pop  when downstream acks
    .RD_DATA    (Adapter_msg_rcvd),
    .REMPTY     (),                     // unused — use RVALID for data-valid
    .RVALID     (Link_data_valid)       // ~REMPTY → data at RD_DATA is valid
);



endmodule