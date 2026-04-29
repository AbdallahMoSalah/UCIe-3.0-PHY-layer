module unit_awak_handshake_tb();
    // clock and handshake signals
    logic lp_awak_req, ungating_done, lclk;
    logic pl_awak_ack, ungating_req;

    // reference FSM state for checking
    typedef enum logic [1:0] { IDLE, UNGATING, ACK } state_t;
    state_t exp_state;

    // expected outputs
    logic exp_ungating_req, exp_pl_awak_ack;

    // instantiate DUT
     unit_awak_handshake DUT (
        .lp_awak_req(lp_awak_req),
        .ungating_done(ungating_done),
        .lclk(lclk),
        .pl_awak_ack(pl_awak_ack),
        .ungating_req(ungating_req)
    );

    // clock generation
    initial begin
        lclk = 0;
        forever #5 lclk = ~lclk;
    end

    // reference model and assertions
    always @(posedge lclk) begin
        case (exp_state)
            IDLE:    if (lp_awak_req)          exp_state <= UNGATING;
            UNGATING:if (ungating_done)        exp_state <= ACK;
            ACK:     if (!lp_awak_req)         exp_state <= IDLE;
            default: exp_state <= IDLE;
        endcase

        exp_ungating_req   = (exp_state == UNGATING);
        exp_pl_awak_ack    = (exp_state == ACK);

        if (ungating_req !== exp_ungating_req)
            $error("[TIME %0t] ungating_req mismatch: got %b expected %b (state=%0d)",
                   $time, ungating_req, exp_ungating_req, exp_state);
        if (pl_awak_ack !== exp_pl_awak_ack)
            $error("[TIME %0t] pl_awak_ack mismatch: got %b expected %b (state=%0d)",
                   $time, pl_awak_ack, exp_pl_awak_ack, exp_state);

    end

    // tasks to drive inputs
    task automatic req_awake();
        @(negedge lclk);
        lp_awak_req <= 1;
    endtask

    task automatic dereq_awake();
        @(negedge lclk);
        lp_awak_req <= 0;
    endtask

    task automatic finish_ungate();
        @(negedge lclk);
        ungating_done <= 1;
    endtask
    
    task automatic reset_ungate();
        @(negedge lclk);
        ungating_done <= 0;
    endtask

    // main stimulus
    initial begin
        lp_awak_req = 0;
        ungating_done = 0;
        exp_state = IDLE;

        $display("--- scenario 1: normal handshake ---");
        req_awake();
        repeat (3) @(negedge lclk);
        finish_ungate();
        repeat (3) @(negedge lclk);
        dereq_awake();
        repeat (3) @(negedge lclk);
        reset_ungate();
        repeat (2) @(negedge lclk);

        $display("--- scenario 2: request without ungating done ---");
        req_awake();
        repeat (5) @(negedge lclk);
        dereq_awake();
        repeat (2) @(negedge lclk);

        $display("--- scenario 3: random toggles ---");
        repeat (1000) begin
            @(negedge lclk);
            lp_awak_req  <= $urandom_range(0,1);
            ungating_done<= $urandom_range(0,1);
        end

        $display("Testbench complete");
        $stop;
    end
endmodule