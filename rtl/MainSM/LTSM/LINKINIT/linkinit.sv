module linkinit(
    import RDI_SM_pkg::*;
    input logic clk,
    input logic rst_n,
    input RDI_state rdi_state_sts,
    input timeout_expired,
    input Linkinit_enable,

    output linkinit_done,
    output timeout_rst_n,
    output enable_timeout,
    output linkinit_error,
    output start_ucie_link_training_rst
);

typedef enum logic [2:0] {
    idle,
    wait_for_rdi_active,
    link_error,
} linkinit_state_t;


always @(posedge clk, negedge rst_n) begin
    if (!rst_n)
        linkinit_state <= idle;
    else begin
        case (linkinit_state)
            idle: begin
                if (Linkinit_enable)
                    linkinit_state <= wait_for_rdi_active;
            end
            wait_for_rdi_active: begin
                if (rdi_state_sts == Active)
                    linkinit_state <= link_error;
            end
            link_error: begin
                if (timeout_expired)
                    linkinit_state <= idle;
            end
        endcase
    end
end

endmodule