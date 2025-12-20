module fpga_top_layer1 (
    input  logic clk,       // 50MHz Clock
    input  logic rst_n,     // Key 0 (Active Low)
    input logic [2:0] sw,
    output logic [7:0] led  // 8 LEDs for Status/Debug
);
    // 1. SETTINGS
    localparam MAPSIZE = 32;
    localparam TOTAL_PIXELS = MAPSIZE * MAPSIZE; // 1024
    localparam OUTPUT_COUNT = 84; // f6

    logic rst;
    assign rst = ~rst_n;

    // 2. MEMORIES (Restored to MIFs)
    // We force "logic" style so reads are Instant (Combinational).
    // This prevents the timing mismatch between hardware and simulation.
    
    (* ramstyle = "logic" *)
    logic signed [7:0]  image_rom  [0:TOTAL_PIXELS-1];
    initial begin
        $readmemh("/home/bany/personal/fpga-dnn-accelerator/image.hex", image_rom);
    end

    (* ramstyle = "M10K", ram_init_file = "golden_f6.mif" *) 
    logic signed [7:0] golden_rom [0:OUTPUT_COUNT-1];

   // 3. STATE MACHINE (Modified for Loading Delay)
    typedef enum { IDLE, WAIT_LOAD, RUN, DONE } state_t; // Added WAIT_LOAD
    state_t state;
    
    // Counter to give the ROMs time to load (needs ~27 cycles, we give 60 for safety)
    logic [5:0] startup_timer; 

    logic start;
    logic data_valid_in;
    logic signed [7:0] pixel_in;
    logic [$clog2(TOTAL_PIXELS):0] read_ptr;
    
    // Outputs from the MUX (Single Channel)
    logic data_valid_out;
    logic signed [7:0] pixel_out;
    logic layer_done;

    // 4. DUT INSTANTIATION (Modified for Parallel)
    
    // Intermediate wires for the 6 parallel channels of c1
    logic [5:0] c1_valid_out;
    logic [5:0][7:0] c1_pixel_out;
    logic [5:0] c1_done;

    lenet_top_parallel DUT (
        .clk(clk), 
        .rst(rst || l2_rst_ctrl), 
        .start(start),
        .data_valid_in(data_valid_in),  
        .pixel_in(pixel_in),
        
        // Connect the arrays
        .data_valid_out(c1_valid_out), 
        .pixel_out(c1_pixel_out),
        .layer_done(c1_done)
    );

    // ============================================================
    // SERIALIZED LAYER 2 (1 Instance looped 16 times)
    // ============================================================
    logic l2_rst_ctrl;
    logic l2_rst_combined;
    logic [3:0] loop_iter;
    logic l2_start;
    logic l2_valid_out;
    logic signed [7:0] l2_pixel_out;
    logic l2_done_sig;
    logic l2_weights_loaded; // Connected to the new output port

    assign l2_rst_combined = rst || l2_rst_ctrl;

    lenet_channel_layer2 U_L2_SERIAL (
        .clk(clk),
        .rst(l2_rst_combined), 
        .start(l2_start),
        .weight_id(loop_iter), // Select weights 0..15
        
        .data_valid_in(c1_valid_out), 
        .pixel_in(c1_pixel_out),
        
        .data_valid_out(l2_valid_out),
        .pixel_out(l2_pixel_out),
        .layer_done(l2_done_sig),
        .loading_done(l2_weights_loaded)
    );

    // BUFFER: Flattened to 1D to ensure M10K inference
    // 16 channels * 25 pixels = 400 words
    (* ramstyle = "logic" *)
    logic signed [7:0] s4_ram [0:399]; 
    logic [4:0] current_pixel_count;

    // STATE MACHINE
    typedef enum { S_IDLE, S_RESET_L2, S_WAIT_LOAD, S_START_L2, S_RUN_L2, S_NEXT, S_SEND_C5, S_BRIDGE_FINISH, S_PRE_START } l2_state_t;
    l2_state_t l2_state;

    // Bridge Counters
    logic [8:0] bridge_rd_ptr; // 0 to 399

    // C5 Connections
    logic signed [7:0] c5_input_pixel;
    logic c5_input_valid;
// ============================================================
    // UNIFIED CONTROL LOGIC (Feeder + L2 Serializer + Bridge)
    // ============================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            // Global & L2 State Reset
            l2_state <= S_IDLE;
            loop_iter <= 0;
            l2_rst_ctrl <= 0;
            startup_timer <= 0;

            // Image Reader Reset
            read_ptr <= 0;
            data_valid_in <= 0;
            pixel_in <= 0;
            start <= 0; 
            
            // Bridge/Buffer Reset
            current_pixel_count <= 0;
            bridge_rd_ptr <= 0;
            c5_input_valid <= 0;
            
        end else begin
            case (l2_state)
                S_IDLE: begin
                    // Wait for FPGA to stabilize (using your existing timer variable)
                    if (startup_timer < 60) begin
                        startup_timer <= startup_timer + 1;
                    end else begin
                        l2_state <= S_RESET_L2;
                        loop_iter <= 0;
                    end
                end

                S_RESET_L2: begin
                    // 1. Reset the Layer 2 Hardware (clears weights)
                    l2_rst_ctrl <= 1; 
                    current_pixel_count <= 0; 
                    
                    // 2. CRITICAL: Reset the Image Feeder for this pass
                    // This forces the image to stream again for the next channel
                    read_ptr <= 0; 
                    data_valid_in <= 0;
                    start <= 0;
                    
                    l2_state <= S_WAIT_LOAD;
                end

                S_WAIT_LOAD: begin
                    l2_rst_ctrl <= 0;
                    // Wait for Layer 2 weights (150 cycles)
                    // This implicitly covers Layer 1 loading (26 cycles), but let's be safe.
                    if (l2_weights_loaded) begin
                        l2_state <= S_PRE_START; // Go to new wait state
                    end
                end

                // NEW STATE: Wait 1 extra cycle to ensure loading_done is stable
                S_PRE_START: begin
                    l2_state <= S_START_L2;
                end

                S_START_L2: begin
                    l2_start <= 1; // Pulse Start for Layer 2
                    start    <= 1; // Pulse Start for Layer 1 (DUT)
                    l2_state <= S_RUN_L2;
                end

                S_RUN_L2: begin
                    l2_start <= 0;
                    start <= 0;
                    
                    // --- A. FEED THE IMAGE (Runs every loop!) ---
                    // This replaces your old "IDLE/RUN/DONE" block
                    if (read_ptr < TOTAL_PIXELS) begin
                        data_valid_in <= 1;
                        pixel_in <= image_rom[read_ptr];
                        read_ptr <= read_ptr + 1;
                    end else begin
                        data_valid_in <= 0;
                    end
                    
                    // --- B. CAPTURE L2 OUTPUT ---
                    if (l2_valid_out) begin
                        // Save result to the specific slot for this loop iteration
                        s4_ram[ (loop_iter * 25) + current_pixel_count ] <= l2_pixel_out;
                        current_pixel_count <= current_pixel_count + 1;
                    end

                    // --- C. CHECK COMPLETION ---
                    if (l2_done_sig) l2_state <= S_NEXT;
                end

                S_NEXT: begin
                    if (loop_iter == 15) begin
                        l2_state <= S_SEND_C5; // All 16 channels done
                    end else begin
                        loop_iter <= loop_iter + 1;
                        l2_state <= S_RESET_L2; // Reset and run again for next channel
                    end
                end

                S_SEND_C5: begin
                    c5_input_valid <= 1;
                    c5_input_pixel <= s4_ram[bridge_rd_ptr];

                    if (bridge_rd_ptr == 399) begin
                        bridge_rd_ptr <= 0;
                        // DO NOT set valid to 0 yet!
                        // Move to a finish state to hold valid high for the last pixel
                        l2_state <= S_BRIDGE_FINISH; 
                    end else begin
                        bridge_rd_ptr <= bridge_rd_ptr + 1;
                    end
                end

                S_BRIDGE_FINISH: begin
                    c5_input_valid <= 0; // Now we can turn it off
                    l2_state <= S_IDLE;
                end
            endcase
        end
    end

    // ============================================================
    // FC CHAINS (C5 -> F6)
    // ============================================================
    logic signed [7:0] c5_out_pixel;
    logic c5_out_valid;
    logic c5_done;

    logic signed [7:0] f6_out_pixel;
    logic f6_out_valid;
    logic f6_done;

    logic signed [7:0] out_out_pixel;
    logic out_out_valid;
    logic out_done;

    // C5 INSTANCE
    fc_streaming #(
        .NUM_INPUTS(400),
        .NUM_OUTPUTS(120),
        .WEIGHT_FILE("/home/bany/personal/fpga-dnn-accelerator/top/weights_generator/fc_weights/c5_weights_flattened.hex"),
        .SHIFT(10)
    ) c5_DUT (
        .clk(clk),
        .rst(rst),
        .data_in(c5_input_pixel),
        .data_valid_in(c5_input_valid),
        .data_out(c5_out_pixel),
        .data_valid_out(c5_out_valid),
        .done(c5_done)
    ); // <--- Don't forget this semicolon!

    // F6 INSTANCE
    fc_streaming #(
        .NUM_INPUTS(120),
        .NUM_OUTPUTS(84),
        .WEIGHT_FILE("/home/bany/personal/fpga-dnn-accelerator/top/weights_generator/fc_weights/f6_weights_flattened.hex"),
        .SHIFT(7)
    ) f6_DUT (
        .clk(clk),
        .rst(rst),
        .data_in(c5_out_pixel),
        .data_valid_in(c5_out_valid),
        .data_out(f6_out_pixel),
        .data_valid_out(f6_out_valid),
        .done(f6_done)
    ); 

    // OUTPUT LAYER
    fc_streaming #(
        .NUM_INPUTS(84),
        .NUM_OUTPUTS(10),
        .WEIGHT_FILE("/home/bany/personal/fpga-dnn-accelerator/top/weights_generator/fc_weights/out_weights_flattened.hex"),
        .ENABLE_RELU(0),
        .SHIFT(7)
    ) out_DUT (
        .clk(clk),
        .rst(rst),
        .data_in(f6_out_pixel),
        .data_valid_in(f6_out_valid),
        .data_out(out_out_pixel),
        .data_valid_out(out_out_valid),
        .done(out_done)
    ); 

    logic [3:0] predicted_digit;
    logic prediction_ready;

    output_max u_argmax (
        .clk(clk),
        .rst(rst),
        .data_in(out_out_pixel),
        .data_valid_in(out_out_valid),
        .layer_done_in(out_done),
        .prediction(predicted_digit),
        .prediction_valid(prediction_ready)
    );

// ============================================================
    //  HEARTBEAT & DEBUG (FIXED FOR DE10-NANO)
    // ============================================================

    // 1. HEARTBEAT TIMER
    logic [25:0] heartbeat;
    always_ff @(posedge clk) begin
        if (rst) heartbeat <= 0;
        else heartbeat <= heartbeat + 1;
    end

    // 2. STICKY DONE LATCHES (NEW: Captures the fast pulses)
    logic c5_done_latched, f6_done_latched, out_done_latched;
    
    always_ff @(posedge clk) begin
        // Reset latches when we start a NEW inference or hard reset
        if (rst || start) begin
            c5_done_latched <= 0;
            f6_done_latched <= 0;
            out_done_latched <= 0;
        end else begin
            // Capture the pulse and HOLD it high
            if (c5_done) c5_done_latched <= 1;
            if (f6_done) f6_done_latched <= 1;
            if (out_done) out_done_latched <= 1;
        end
    end

    // 3. DEFINE SPY REGISTERS (Debug Memory)
    logic signed [7:0] peak_c1_val;
    logic signed [7:0] peak_l2_val;
    logic signed [7:0] peak_c5_val;
    logic signed [7:0] peak_f6_val;
    
    logic signed [7:0] winning_score;
    logic [3:0]        winner_index;    
    logic [3:0]        stream_index;

    // 4. CAPTURE PEAK DATA (The Spy Logic)
    always_ff @(posedge clk) begin
        if (start) begin
            peak_c1_val <= 0;
            peak_l2_val <= 0;
            peak_c5_val <= 0;
            peak_f6_val <= 0;
        end 
        else begin
            // Spy on peaks (Max Value Hold)
            if (c1_valid_out[0] && c1_pixel_out[0] > peak_c1_val) peak_c1_val <= c1_pixel_out[0];
            if (l2_valid_out    && l2_pixel_out    > peak_l2_val) peak_l2_val <= l2_pixel_out;
            if (c5_out_valid    && c5_out_pixel    > peak_c5_val) peak_c5_val <= c5_out_pixel;
            if (f6_out_valid    && f6_out_pixel    > peak_f6_val) peak_f6_val <= f6_out_pixel;
        end

        // Final Score Capture
        if (rst) begin
            winning_score <= -128;
            stream_index <= 0;
        end else if (out_out_valid) begin
            if (out_out_pixel > winning_score) begin
                winning_score <= out_out_pixel;
                winner_index <= stream_index;
            end
            
            if (stream_index == 9) stream_index <= 0;
            else stream_index <= stream_index + 1;
        end
    end

    // ============================================================
    // THE DOWNSTREAM DEBUGGER (Uses SW[2], SW[1], SW[0])
    // ============================================================
    always_comb begin
        led = 8'b00000000;
        
        case (sw[2:0]) 
            // MODE 0: PREDICTION + STATUS
            // Shows prediction on [3:0], but uses upper LEDs for status
            3'b000: begin 
                led[3:0] = winner_index;
                led[4]   = prediction_ready; // Done with everything
                led[5]   = c5_done_latched;  // Did Layer 3 finish?
                led[6]   = f6_done_latched;  // Did Layer 4 finish?
                led[7]   = heartbeat[25];    // Is Clock alive?
            end

            // MODE 1: C1 SATURATION (Check for 127)
            3'b001: led[7:0] = peak_c1_val;

            // MODE 2: L2 SATURATION
            3'b010: led[7:0] = peak_l2_val;

            // MODE 3: C5 SATURATION
            3'b011: led[7:0] = peak_c5_val;

            // MODE 4: F6 SATURATION
            3'b100: led[7:0] = peak_f6_val;

            // MODE 5: CONFIDENCE SCORE
            3'b101: led[7:0] = winning_score;

            // MODE 6: STICKY DEBUG (NEW)
            // Explicitly shows which layers have finished
            3'b110: begin
                led[0] = c1_done[0];       // C1 Live status
                led[1] = l2_weights_loaded;// Weights Loaded
                led[2] = l2_done_sig;      // L2 Done
                led[3] = c5_done_latched;  // C5 Done (Sticky)
                led[4] = f6_done_latched;  // F6 Done (Sticky)
                led[5] = out_done_latched; // Out Done (Sticky)
                led[7] = 1;                // Marker for this mode
            end

            default: led = 8'b11111111; // Error Pattern
        endcase
    end

endmodule