module unit_clk_pattern_detector_rx( //Abdallah
    input  logic i_clk,
    input  logic i_rst_n,
    input  logic clk_detector_en,

    input  logic clk_p,
    input  logic clk_n,
    input  logic track,

    
    output logic clk_p_pattern_pass,
                 clk_n_pattern_pass,
                 track_pattern_pass
);

parameter MAIN   = 128;
parameter TOGGLE = 16;
parameter ZERO   = 8;



logic [4:0] counter_toggle_p;
logic [4:0] counter_toggle_n;
logic [4:0] counter_toggle_track;
logic [3:0] counter_zero_p;
logic [3:0] counter_zero_n;
logic [3:0] counter_zero_track;

logic [4:0] counter_16_consecetive_p;
logic [4:0] counter_16_consecetive_n;
logic [4:0] counter_16_consecetive_track;
logic clk_p_p_w , clk_p_n_w , clk_n_p_w , clk_n_n_w , track_p_w , track_n_w; 
logic flag_p_tog , flag_p_zero , flag_n_tog , flag_n_zero , flag_track_tog , flag_track_zero ;


always @(posedge i_clk , negedge i_rst_n ) begin
    if (!i_rst_n) begin
        counter_toggle_p    <= 0;
        counter_toggle_n    <= 0;
        counter_toggle_track    <= 0;
        counter_zero_p <= 0;
        counter_zero_n <= 0;
        counter_zero_track <= 0;
        counter_16_consecetive_p <= 0;
        counter_16_consecetive_n <= 0;
        counter_16_consecetive_track <= 0;
        clk_p_p_w <= 0; 
        clk_p_n_w <= 0; 
        clk_n_p_w <= 0; 
        clk_n_n_w <= 0; 
        track_p_w <= 0; 
        track_n_w <= 0;
        flag_p_tog <= 0; 
        flag_p_zero <= 0; 
        flag_n_tog <= 0; 
        flag_n_zero <= 0; 
        flag_track_tog <= 0; 
        flag_track_zero <= 0; 
        clk_p_pattern_pass <= 0;
        clk_n_pattern_pass <= 0;
        track_pattern_pass <= 0;
    end
    else begin

        if (!clk_detector_en) begin
       counter_toggle_p    <= 0;
        counter_toggle_n    <= 0;
        counter_toggle_track    <= 0;
        counter_zero_p <= 0;
        counter_zero_n <= 0;
        counter_zero_track <= 0;
        counter_16_consecetive_p <= 0;
        counter_16_consecetive_n <= 0;
        counter_16_consecetive_track <= 0;
        clk_p_p_w <= 0; 
        clk_p_n_w <= 0; 
        clk_n_p_w <= 0; 
        clk_n_n_w <= 0; 
        track_p_w <= 0; 
        track_n_w <= 0;
        flag_p_tog <= 0; 
        flag_p_zero <= 0; 
        flag_n_tog <= 0; 
        flag_n_zero <= 0; 
        flag_track_tog <= 0; 
        flag_track_zero <= 0; 
        clk_p_pattern_pass <= 0;
        clk_n_pattern_pass <= 0;
        track_pattern_pass <= 0;
        end

        else begin
            clk_p_p_w <= clk_p;
            clk_n_p_w <= clk_n;
            track_p_w <= track;
   
        end
    end
end

always @(negedge i_clk , negedge i_rst_n ) begin
    if (!i_rst_n) begin
        counter_toggle_p    <= 0;
        counter_toggle_n    <= 0;
        counter_toggle_track    <= 0;
        counter_zero_p <= 0;
        counter_zero_n <= 0;
        counter_zero_track <= 0;
        counter_16_consecetive_p <= 0;
        counter_16_consecetive_n <= 0;
        counter_16_consecetive_track <= 0;
        clk_p_p_w <= 0; 
        clk_p_n_w <= 0; 
        clk_n_p_w <= 0; 
        clk_n_n_w <= 0; 
        track_p_w <= 0; 
        track_n_w <= 0;
        flag_p_tog <= 0; 
        flag_p_zero <= 0; 
        flag_n_tog <= 0; 
        flag_n_zero <= 0; 
        flag_track_tog <= 0; 
        flag_track_zero <= 0; 
        clk_p_pattern_pass <= 0;
        clk_n_pattern_pass <= 0;
        track_pattern_pass <= 0;
    end
    else begin

        if (!clk_detector_en) begin
        counter_toggle_p    <= 0;
        counter_toggle_n    <= 0;
        counter_toggle_track    <= 0;
        counter_zero_p <= 0;
        counter_zero_n <= 0;
        counter_zero_track <= 0;
        counter_16_consecetive_p <= 0;
        counter_16_consecetive_n <= 0;
        counter_16_consecetive_track <= 0;
        clk_p_p_w <= 0; 
        clk_p_n_w <= 0; 
        clk_n_p_w <= 0; 
        clk_n_n_w <= 0; 
        track_p_w <= 0; 
        track_n_w <= 0;
        flag_p_tog <= 0; 
        flag_p_zero <= 0; 
        flag_n_tog <= 0; 
        flag_n_zero <= 0; 
        flag_track_tog <= 0; 
        flag_track_zero <= 0; 
        clk_p_pattern_pass <= 0;
        clk_n_pattern_pass <= 0;
        track_pattern_pass <= 0;
        end

        else begin
            clk_p_n_w <= clk_p;
            clk_n_n_w <= clk_n;
            track_n_w <= track;

        end
    end
end

always @(posedge i_clk , negedge i_rst_n ) begin
    if (!i_rst_n) begin
      counter_toggle_p    <= 0;
        counter_toggle_n    <= 0;
        counter_toggle_track    <= 0;
        counter_zero_p <= 0;
        counter_zero_n <= 0;
        counter_zero_track <= 0;
        counter_16_consecetive_p <= 0;
        counter_16_consecetive_n <= 0;
        counter_16_consecetive_track <= 0;
        clk_p_p_w <= 0; 
        clk_p_n_w <= 0; 
        clk_n_p_w <= 0; 
        clk_n_n_w <= 0; 
        track_p_w <= 0; 
        track_n_w <= 0;
        flag_p_tog <= 0; 
        flag_p_zero <= 0; 
        flag_n_tog <= 0; 
        flag_n_zero <= 0; 
        flag_track_tog <= 0; 
        flag_track_zero <= 0; 
        clk_p_pattern_pass <= 0;
        clk_n_pattern_pass <= 0;
        track_pattern_pass <= 0;
    end
    else begin

        if (!clk_detector_en) begin
        counter_toggle_p    <= 0;
        counter_toggle_n    <= 0;
        counter_toggle_track    <= 0;
        counter_zero_p <= 0;
        counter_zero_n <= 0;
        counter_zero_track <= 0;
        counter_16_consecetive_p <= 0;
        counter_16_consecetive_n <= 0;
        counter_16_consecetive_track <= 0;
        clk_p_p_w <= 0; 
        clk_p_n_w <= 0; 
        clk_n_p_w <= 0; 
        clk_n_n_w <= 0; 
        track_p_w <= 0; 
        track_n_w <= 0;
        flag_p_tog <= 0; 
        flag_p_zero <= 0; 
        flag_n_tog <= 0; 
        flag_n_zero <= 0; 
        flag_track_tog <= 0; 
        flag_track_zero <= 0; 
        clk_p_pattern_pass <= 0;
        clk_n_pattern_pass <= 0;
        track_pattern_pass <= 0;
        end

        else begin 

            // positive clk
            //toggle
            if (clk_p_p_w ^ clk_p_n_w == 1) begin

                counter_toggle_p <= counter_toggle_p + 1; 
                counter_zero_p <= 0;                      
                flag_p_zero <= 0;                         
                
                if (counter_zero_p < ZERO && counter_zero_p != 0 ) begin
                    counter_16_consecetive_p <= 0;
                end     

                if (counter_toggle_p == TOGGLE-1 ) begin
                    flag_p_tog <= 1;
                end else if (counter_toggle_p > TOGGLE-1) begin
                    flag_p_tog <= 0;
                end
                   //idle
            end else if (clk_p_p_w ^ clk_p_n_w == 0 ) begin
            
                counter_zero_p <= counter_zero_p + 1;   
                counter_toggle_p <= 0;  
                
                if (counter_toggle_p < TOGGLE && counter_toggle_p != 0) begin
                    counter_16_consecetive_p <= 0;
                end  

                if (counter_zero_p == ZERO-1 ) begin
                    flag_p_zero <= 1;       //
                end else if (counter_zero_p > ZERO) begin
                    flag_p_zero <= 0;
                    if (counter_16_consecetive_p <= TOGGLE-1) begin
                    counter_16_consecetive_p <= 0;
                    end
                end  
            end 
             // negative clk
             //toggle
            if (clk_n_p_w ^ clk_n_n_w == 1) begin

                counter_toggle_n <= counter_toggle_n + 1; 
                counter_zero_n <= 0;                      
                flag_n_zero <= 0;                         
                
                if (counter_zero_n < ZERO && counter_zero_n != 0 ) begin
                    counter_16_consecetive_n <= 0;
                end     

                if (counter_toggle_n == TOGGLE-1 ) begin
                    flag_n_tog <= 1;
                end else if (counter_toggle_n > TOGGLE-1) begin
                    flag_n_tog <= 0;
                end
                   //idle
            end else if (clk_n_p_w ^ clk_n_n_w == 0 ) begin
            
                counter_zero_n <= counter_zero_n + 1;   
                counter_toggle_n <= 0;  
                
                if (counter_toggle_n < TOGGLE && counter_toggle_n != 0) begin
                    counter_16_consecetive_n <= 0;
                end  

                if (counter_zero_n == ZERO-1 ) begin
                    flag_n_zero <= 1;       //
                end else if (counter_zero_n > ZERO) begin
                    flag_n_zero <= 0;
                    if (counter_16_consecetive_n <= TOGGLE-1) begin
                    counter_16_consecetive_n <= 0;
                    end
                end
            end
            // track
            //toggle
            if (track_p_w ^ track_n_w == 1) begin

                counter_toggle_track <= counter_toggle_track + 1; 
                counter_zero_track <= 0;                      
                flag_track_zero <= 0;                         
                
                if (counter_zero_track < ZERO && counter_zero_track != 0 ) begin
                    counter_16_consecetive_track <= 0;
                end     

                if (counter_toggle_track == TOGGLE-1 ) begin
                    flag_track_tog <= 1;
                end else if (counter_toggle_track > TOGGLE-1) begin
                    flag_track_tog <= 0;
                end
                   //idle
            end else if (track_p_w ^ track_n_w == 0 ) begin
            
                counter_zero_track <= counter_zero_track + 1;   
                counter_toggle_track <= 0;  
                
                if (counter_toggle_track < TOGGLE && counter_toggle_track != 0) begin
                    counter_16_consecetive_track <= 0;
                end  

                if (counter_zero_track == ZERO-1 ) begin
                    flag_track_zero <= 1;       
                end else if (counter_zero_track > ZERO) begin
                    flag_track_zero <= 0;
                    if (counter_16_consecetive_track <= TOGGLE-1 ) begin
                    counter_16_consecetive_track <= 0;
                    end
                end
            end

            if (flag_p_tog && flag_p_zero) begin  
                counter_16_consecetive_p <= counter_16_consecetive_p + 1;
                flag_p_tog <= 0;
                flag_p_zero <= 0;
            end
              if (flag_n_tog && flag_n_zero) begin 
                counter_16_consecetive_n <= counter_16_consecetive_n + 1;
                flag_n_tog <= 0;
                flag_n_zero <= 0;
            end
              if (flag_track_tog && flag_track_zero) begin 
                counter_16_consecetive_track <= counter_16_consecetive_track + 1;
                flag_track_tog <= 0;
                flag_track_zero <= 0;
            end
            if (counter_16_consecetive_p == 16) begin
                clk_p_pattern_pass <= 1;
            end
            if (counter_16_consecetive_n == 16) begin
                clk_n_pattern_pass <= 1;
            end
            if (counter_16_consecetive_track == 16) begin
                track_pattern_pass <= 1;
            end

            
                   end
    end 
end

endmodule
            
      