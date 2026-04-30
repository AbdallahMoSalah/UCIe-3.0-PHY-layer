// =============================================================================
//  credit_counter
//  UCIe Sideband RDI Controller – Flow-Control Credit Tracker
//
//  Purpose
//  ───────
//  Tracks the number of outstanding sideband-request slots available for
//  forwarding upstream packets from the link to the de-aggregator/adapter.
//
//  Credit Rules (UCIe §11)
//  ───────────────────────
//   • Initial credits  = CRD_INIT  (loaded at reset)
//   • INC  (+1)  : a credit is returned by the peer  (crd_in  pulse)
//   • DEC  (-1)  : a request is consumed/forwarded    (crd_out pulse)
//   • Simultaneous INC+DEC : count unchanged          (net zero)
//   • Saturating : never above 2^CRD_W-1, never below 0
//
//  Outputs
//  ───────
//   no_crd  : asserted when count == 0; used by rdi_rx_arbiter to
//             block forwarding new requests until a credit arrives.
//
// =============================================================================

module credit_counter #(
    parameter int CRD_W    = 5,          // counter width  (max = 2^CRD_W - 1)
    parameter int CRD_INIT = 4           // credits at reset
)(
    input  logic clk,
    input  logic rst_n,

    input  logic crd_in,        // +1 : credit received from peer (lp_cfg_crd)
    input  logic crd_out,       // -1 : credit consumed (request forwarded)

    output logic no_crd         // 1 when count == 0 (gate requests)
);

    logic [CRD_W-1:0] count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= CRD_W'(CRD_INIT-1);
        end else begin
            case ({crd_in, crd_out})
                // inc only – guard against overflow
                2'b10 : count <= (count == '1)        ? count : count + 1'b1;
                // dec only – guard against underflow
                2'b01 : count <= (count == '0)        ? count : count - 1'b1;
                // both simultaneously – net zero
                2'b11 : count <= count;
                // no change
                default: count <= count;
            endcase
        end
    end

    assign no_crd = (count == '0);

endmodule
