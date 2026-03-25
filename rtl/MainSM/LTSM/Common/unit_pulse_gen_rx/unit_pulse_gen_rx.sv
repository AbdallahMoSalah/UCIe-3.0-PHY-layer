
module unit_pulse_gen_rx #(
        parameter NUM_STAGES = 2,    // Number of Flip Flop Stages.
        parameter BUS_WIDTH  = 64+16 // Width of synchronized bus.
    ) (
        input  wire                 CLK         , // Destination domain clock.
        input  wire                 RST         , // Destination domain Active Low Asynchronous Reset.
        input  wire [BUS_WIDTH-1:0] unsync_bus  , // Unsyncronized bus.
        output reg  [BUS_WIDTH-1:0] sync_bus    , // Synchronized bit/bus.
        input  wire                 bus_enable  , // Source domain enable signal.
        output reg                  enable_pulse  // destination domain enable signal.
    );
    reg  [NUM_STAGES-1 : 0] multi_ff    ; // To store the values of the Flip-Flop Stages. (Before the Pulse Generator block)
    reg                     ff_pulse_gen; // To store the previous value of the case if the mux was enabled to know if the enable signal has enabled in the previous cycle.
    wire                    mux_selector;
    //===========================//
    //  Multi Flip-Flop Stages   //
    //===========================//
    always @(posedge CLK or negedge RST) begin
        if(!RST) begin
            multi_ff <= 0;
        end
        else begin
            multi_ff <= {multi_ff[NUM_STAGES-2:0], bus_enable};
        end
    end


    //===========================//
    //   Pulse Generator Block   //
    //===========================//
    always @(posedge CLK or negedge RST) begin
        if(!RST) begin
            ff_pulse_gen <= 0;
        end
        else begin
            ff_pulse_gen <= multi_ff[NUM_STAGES-1];
        end
    end

    assign mux_selector = (!ff_pulse_gen & multi_ff[NUM_STAGES-1]);



    //==================================//
    //    output pin 'enable_pulse'     //
    //==================================//
    always @(posedge CLK or negedge RST) begin
        if(!RST) begin
            enable_pulse <= 0;
        end
        else begin
            enable_pulse <= mux_selector;
        end
    end


    //==================================//
    //      output pin 'sync_bus'       //
    //==================================//
    always @(posedge CLK or negedge RST) begin
        if(!RST) begin
            sync_bus <= 'd0;
        end
        else if(mux_selector) begin
            sync_bus <= unsync_bus;
        end
    end


endmodule
