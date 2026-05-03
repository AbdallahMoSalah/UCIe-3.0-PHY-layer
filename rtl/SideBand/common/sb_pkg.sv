`timescale 1ns/1ps
package sb_pkg;

parameter SB_FREQ = 100.0; // MHz
parameter  SB_CLK = (1000/SB_FREQ);

parameter  SERDES_FREQ = 800.0; // MHz
parameter  SERDES_CLK = (1000/SERDES_FREQ);

  typedef enum logic [4:0] {  //Opcode enum
    SB_32_MEM_READ                = 5'b00000,
    SB_32_MEM_WRITE               = 5'b00001,
    SB_32_DMS_REG_READ            = 5'b00010,
    SB_32_DMS_REG_WRITE           = 5'b00011,
    SB_32_CFG_READ                = 5'b00100,
    SB_32_CFG_WRITE               = 5'b00101,
    SB_64_MEM_READ                = 5'b01000,
    SB_64_MEM_WRITE               = 5'b01001,
    SB_64_DMS_REG_READ            = 5'b01010,
    SB_64_DMS_REG_WRITE           = 5'b01011,
    SB_64_CFG_READ                = 5'b01100,
    SB_64_CFG_WRITE               = 5'b01101,
    SB_COMPLETION_WITHOUT_DATA    = 5'b10000,
    SB_COMPLETION_WITH_32_DATA    = 5'b10001,
    SB_MSG_WITHOUT_DATA           = 5'b10010,
    SB_MNGT_PORT_MSG_WITHOUT_DATA = 5'b10111,
    SB_MNGT_PORT_MSG_WITH_DATA    = 5'b11000,
    SB_COMPLETION_WITH_64_DATA    = 5'b11001,
    SB_MSG_WITH_64_DATA           = 5'b11011,
    SB_PRIORITY_MSG1              = 5'b11110,
    SB_PRIORITY_MSG2              = 5'b11111
  } sb_opcode_e;

  typedef enum logic [2:0] {  //srcid enum
    STACK0        = 3'b000,
    ADAPTER       = 3'b001,
    PHY           = 3'b010,
    MNGT_PORT_SRC = 3'b011,
    STACK1        = 3'b100
  } sb_srcid_e;

  typedef enum logic [2:0] {  //dstid enum
    LOCAL_ADAPTER     = 3'b001,
    LOCAL_PHY         = 3'b010,
    REMOTE_ADAPTER    = 3'b101,
    REMOTE_PHY        = 3'b110,
    REMOTE_REG_ACCESS = 3'b100,
    MNGT_PORT_DST     = 3'b111
  } sb_dstid_e;

/*   typedef enum logic [3:0] {  //RDI message number enum
    ACTIVE_REQ = 4'b0000,
    L1_REQ = 4'b0001,
    L2_REQ = 4'b0010,
    LINK_RESET_REQ = 4'b0011,
    LINK_ERROR_REQ = 4'b0100,
    RETRAIN_REQ = 4'b0101,
    DISABLE_REQ = 4'b0110,
    ACTIVE_RSP = 4'b0111,
    PMNAK_RSP = 4'b1000,
    L1_RSP = 4'b1001,
    L2_RSP = 4'b1010,
    LINK_RESET_RSP = 4'b1011,
    LINK_ERROR_RSP = 4'b1100,
    RETRAIN_RSP = 4'b1101,
    DISABLE_RSP = 4'b1110,
    NOOP = 4'b1111
  } sb_rdi_msg_no_e;
 */
  typedef enum logic [7:0] {
    SBINIT_OFFRESET_DOMAIN    = 8'h91,
    RX_TEST_SWEEP_DONE_RESULT = 8'h81,
    SBINIT_REQ_DOMAIN         = 8'h95,
    SBINIT_RESP_DOMAIN        = 8'h9A,
    MBINIT_REQ_DOMAIN         = 8'hA5,
    MBINIT_RESP_DOMAIN        = 8'hAA,
    MBTRAIN_REQ_DOMAIN        = 8'hB5,
    MBTRAIN_RESP_DOMAIN       = 8'hBA,
    RECAL_REQ_DOMAIN          = 8'hD5,
    RECAL_RESP_DOMAIN         = 8'hDA,
    PHYRETRAIN_REQ_DOMAIN     = 8'hC5,
    PHYRETRAIN_RESP_DOMAIN    = 8'hCA,
    TRAINERROR_REQ_DOMAIN     = 8'hE5,
    TRAINERROR_RESP_DOMAIN    = 8'hEA,
    RDI_REQ_DOMAIN            = 8'h01,
    RDI_RESP_DOMAIN           = 8'h02,
    TEST_REQ_DOMAIN           = 8'h85,
    TEST_RESP_DOMAIN          = 8'h8A
  } msg_code_e;



  typedef struct packed {
    logic        dp;          // [63]
    logic        cp;          // [62]
    logic        cr;          // [61]
    logic [1:0]  rsvd2;       // [60:59]
    sb_dstid_e   dstid;       // [58:56]
    logic [23:0] addr;        // [55:32]
    sb_srcid_e   srcid;       // [31:29]
    logic [3:0]  rsvd1;       // [28:25]
    logic [4:0]  tag;         // [24:20]
    logic [7:0]  be;          // [19:12]
    logic [5:0]  rsvd0;       // [11:6]
    logic        ep;          // [5]
    sb_opcode_e  opcode;      // [4:0]
  } sb_req_header_t;

  typedef struct packed {
    logic        dp;          // [63]
    logic        cp;          // [62]
    logic        cr;          // [61]
    logic [1:0]  rsvd3;       // [60:59]
    sb_dstid_e   dstid;       // [58:56]
    logic [20:0] rsvd2;       // [55:35]
    logic [2:0]  status;      // [34:32]
    sb_srcid_e   srcid;       // [31:29]
    logic [3:0]  rsvd1;       // [28:25]
    logic [4:0]  tag;         // [24:20]
    logic [7:0]  be;          // [19:12]
    logic [5:0]  rsvd0;       // [11:6]
    logic        ep;          // [5]
    sb_opcode_e  opcode;      // [4:0]
  } sb_cpl_header_t;

  typedef struct packed {
    logic        dp;          // [63]
    logic        cp;          // [62]
    logic [2:0]  rsvd2;       // [61:59]
    sb_dstid_e   dstid;       // [58:56]
    logic [15:0] MsgInfo;     // [55:40]
    logic [7:0]  MsgSubcode;  // [39:32]
    sb_srcid_e   srcid;       // [31:29]
    logic [4:0]  rsvd1;       // [28:24]
    msg_code_e   msgcode;     // [23:16]
    logic [10:0] rsvd0;       // [15:5]
    sb_opcode_e  opcode;      // [4:0]
  } sb_msg_header_t;

  typedef union packed {
    logic [63:0]    raw;
    sb_req_header_t req;
    sb_cpl_header_t cpl;
    sb_msg_header_t msg;
  } sb_header_u;

  typedef struct packed {
    logic [63:0] payload;  // [127:64]
    sb_header_u  header;   // [63:0]
  } sb_packet_t;

endpackage