module fpga_top_layer1 (
    input  logic clk,       // 50MHz Clock
    input  logic rst_n,     // Key 0 (Active Low)
    input  logic [2:0] sw,
    input  logic [7:0] led_dummy,
    output logic [7:0] led,
    
    // HPS Bridge Connections
    output logic [31:0] image_addr,
    input  logic [31:0] qsys_readdata
);

    // 1. SETTINGS
    localparam MAPSIZE = 32;
    localparam TOTAL_PIXELS = 1024;
    
    logic rst;
    assign rst = ~rst_n;

    // 2. STATE MACHINE
    typedef enum { S_IDLE, S_RESET_L2, S_WAIT_LOAD, S_START_L2, S_RUN_L2, S_NEXT, S_SEND_C5, S_BRIDGE_FINISH, S_PRE_START } l2_state_t;
    l2_state_t l2_state;

    // Timers & Counters
    logic [5:0] startup_timer;
    logic [3:0] loop_iter;
    logic [4:0] current_pixel_count;
    logic [8:0] bridge_rd_ptr;
    
    // Neural Net Signals
    logic start;
    logic l2_rst_ctrl;
    logic l2_weights_loaded;
    
    // Debug Wires (Signed for correct comparison)
    logic [5:0] c1_valid_out;
    logic signed [5:0][7:0] c1_pixel_out;
    logic [5:0] c1_done;

    // 3. THE TIMING FIX (REDUCED TO 1 CYCLE)
    // =========================================================
    logic [$clog2(TOTAL_PIXELS):0] read_ptr;
    logic signed [7:0] pixel_from_bridge;
    logic data_valid_in;

    // 1. Use the read_ptr directly (Do NOT shift by 2)
    assign image_addr = {20'b0, read_ptr[$clog2(TOTAL_PIXELS):2]};

    // 2. Select the correct byte from the 32-bit bus
    logic [1:0] byte_select;

    // We need to delay the selector to match the memory read latency (usually 1 or 2 cycles)
    // Assuming 1 cycle latency for on-chip RAM/Bridge:
    always_ff @(posedge clk) begin
        byte_select <= read_ptr[1:0]; // Store the bottom 2 bits
    end

    // 3. MUX: Pick the byte based on the offset
    always_comb begin
        case (byte_select)
            2'b00: pixel_from_bridge = qsys_readdata[7:0];   // Bytes 0, 4, 8...
            2'b01: pixel_from_bridge = qsys_readdata[15:8];  // Bytes 1, 5, 9...
            2'b10: pixel_from_bridge = qsys_readdata[23:16]; // Bytes 2, 6, 10...
            2'b11: pixel_from_bridge = qsys_readdata[31:24]; // Bytes 3, 7, 11...
        endcase
    end

    // Use 'pixel_from_bridge' as your input to the Neural Net

    // C. Fix Timing: EXACT 1-Cycle Delay (Standard RAM Latency)
    // Cycle 0: read_ptr updates -> Address changes on bus.
    // Cycle 1: Memory returns Data. 'data_valid_in' becomes 1. MATCH.
    always_ff @(posedge clk) begin
        if (rst) begin
            data_valid_in <= 0;
        end else begin
            // Simply check if we are reading. The register itself acts as the 1-cycle delay.
            if (read_ptr < TOTAL_PIXELS && l2_state == S_RUN_L2) 
                data_valid_in <= 1;
            else 
                data_valid_in <= 0;
        end
    end
    // =========================================================

    // 4. DUT INSTANTIATION
    lenet_top_parallel DUT (
        .clk(clk), 
        .rst(rst || l2_rst_ctrl), 
        .start(start),
        .data_valid_in(data_valid_in),     
        .pixel_in(pixel_from_bridge),      
        .data_valid_out(c1_valid_out), 
        .pixel_out(c1_pixel_out),
        .layer_done(c1_done)
    );

    // SERIALIZED LAYER 2
    logic l2_start, l2_valid_out, l2_done_sig;
    logic signed [7:0] l2_pixel_out;

    lenet_channel_layer2 U_L2_SERIAL (
        .clk(clk),
        .rst(rst || l2_rst_ctrl), 
        .start(l2_start),
        .weight_id(loop_iter),
        .data_valid_in(c1_valid_out), 
        .pixel_in(c1_pixel_out),
        .data_valid_out(l2_valid_out),
        .pixel_out(l2_pixel_out),
        .layer_done(l2_done_sig),
        .loading_done(l2_weights_loaded)
    );

    // BUFFER RAM
    (* ramstyle = "logic" *)
    logic signed [7:0] s4_ram [0:399];

    // C5 -> F6 -> OUT
    logic c5_input_valid;
    logic signed [7:0] c5_input_pixel;
    logic c5_out_valid, f6_out_valid, out_out_valid;
    logic signed [7:0] c5_out_pixel, f6_out_pixel, out_out_pixel;
    logic c5_done, f6_done, out_done;

    fc_streaming #(.NUM_INPUTS(400), .NUM_OUTPUTS(120), .WEIGHT_FILE("/home/bany/personal/fpga-dnn-accelerator/top/weights_generator/fc_weights/c5_weights_flattened.hex"), .SHIFT(10)) c5_DUT (
        .clk(clk), .rst(rst), .data_in(c5_input_pixel), .data_valid_in(c5_input_valid), .data_out(c5_out_pixel), .data_valid_out(c5_out_valid), .done(c5_done));

    fc_streaming #(.NUM_INPUTS(120), .NUM_OUTPUTS(84), .WEIGHT_FILE("/home/bany/personal/fpga-dnn-accelerator/top/weights_generator/fc_weights/f6_weights_flattened.hex"), .SHIFT(7)) f6_DUT (
        .clk(clk), .rst(rst), .data_in(c5_out_pixel), .data_valid_in(c5_out_valid), .data_out(f6_out_pixel), .data_valid_out(f6_out_valid), .done(f6_done));

    fc_streaming #(.NUM_INPUTS(84), .NUM_OUTPUTS(10), .WEIGHT_FILE("/home/bany/personal/fpga-dnn-accelerator/top/weights_generator/fc_weights/out_weights_flattened.hex"), .ENABLE_RELU(0), .SHIFT(7)) out_DUT (
        .clk(clk), .rst(rst), .data_in(f6_out_pixel), .data_valid_in(f6_out_valid), .data_out(out_out_pixel), .data_valid_out(out_out_valid), .done(out_done));

    // PREDICTION LOGIC
    logic [3:0] predicted_digit;
    logic prediction_ready;
    output_max u_argmax (.clk(clk), .rst(rst), .data_in(out_out_pixel), .data_valid_in(out_out_valid), .layer_done_in(out_done), .prediction(predicted_digit), .prediction_valid(prediction_ready));

    // ============================================================
    // CONTROL LOGIC
    // ============================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            l2_state <= S_IDLE;
            loop_iter <= 0;
            l2_rst_ctrl <= 0;
            startup_timer <= 0;
            read_ptr <= 0;
            start <= 0; 
            current_pixel_count <= 0;
            bridge_rd_ptr <= 0;
            c5_input_valid <= 0;
        end else begin
            case (l2_state)
                S_IDLE: begin
                    if (led_dummy[0] == 1) begin
                        l2_state <= S_RESET_L2;
                        loop_iter <= 0;
                    end
                end
                S_RESET_L2: begin
                    l2_rst_ctrl <= 1;
                    current_pixel_count <= 0; 
                    read_ptr <= 0;
                    start <= 0;
                    l2_state <= S_WAIT_LOAD;
                end

                S_WAIT_LOAD: begin
                    l2_rst_ctrl <= 0;
                    if (l2_weights_loaded) l2_state <= S_PRE_START;
                end

                S_PRE_START: l2_state <= S_START_L2;

                S_START_L2: begin
                    l2_start <= 1;
                    start    <= 1;
                    l2_state <= S_RUN_L2;
                end

                S_RUN_L2: begin
                    l2_start <= 0;
                    start <= 0;
                    
                    // --- A. FEED THE IMAGE ---
                    if (read_ptr < TOTAL_PIXELS) begin
                        read_ptr <= read_ptr + 1;
                    end
                    // valid signal is handled in the "Timing Fix" block above
                    
                    // --- B. CAPTURE L2 OUTPUT ---
                    if (l2_valid_out) begin
                        s4_ram[ (loop_iter * 25) + current_pixel_count ] <= l2_pixel_out;
                        current_pixel_count <= current_pixel_count + 1;
                    end

                    // --- C. CHECK COMPLETION ---
                    if (l2_done_sig) l2_state <= S_NEXT;
                end

                S_NEXT: begin
                    if (loop_iter == 15) l2_state <= S_SEND_C5;
                    else begin
                        loop_iter <= loop_iter + 1;
                        l2_state <= S_RESET_L2;
                    end
                end

                S_SEND_C5: begin
                    c5_input_valid <= 1;
                    c5_input_pixel <= s4_ram[bridge_rd_ptr];
                    if (bridge_rd_ptr == 399) begin
                        bridge_rd_ptr <= 0;
                        l2_state <= S_BRIDGE_FINISH;
                    end else begin
                        bridge_rd_ptr <= bridge_rd_ptr + 1;
                    end
                end

                S_BRIDGE_FINISH: begin
                    c5_input_valid <= 0;
                    if (led_dummy[0] == 0) begin
                        l2_state <= S_IDLE;
                    end
                end
            endcase
        end
    end

    // ============================================================
    // DEBUG / SPY LOGIC
    // ============================================================
    logic c5_done_latched, f6_done_latched, out_done_latched;
    logic signed [7:0] peak_c1_val, peak_l2_val, peak_c5_val, peak_f6_val, winning_score;
    logic [3:0] winner_index, stream_index;
    
    // Done Latches
    always_ff @(posedge clk) begin
        if (rst || start) begin
            c5_done_latched <= 0; f6_done_latched <= 0; out_done_latched <= 0;
        end else begin
            if (c5_done) c5_done_latched <= 1;
            if (f6_done) f6_done_latched <= 1;
            if (out_done) out_done_latched <= 1;
        end
    end

    // Spy Logic
    always_ff @(posedge clk) begin
        if (start) begin
            peak_c1_val <= -128; peak_l2_val <= -128; peak_c5_val <= -128; peak_f6_val <= -128;
        end else begin
            if (c1_valid_out[0] && $signed(c1_pixel_out[0]) > peak_c1_val) peak_c1_val <= c1_pixel_out[0];
            if (l2_valid_out    && l2_pixel_out             > peak_l2_val) peak_l2_val <= l2_pixel_out;
            if (c5_out_valid    && c5_out_pixel             > peak_c5_val) peak_c5_val <= c5_out_pixel;
            if (f6_out_valid    && f6_out_pixel             > peak_f6_val) peak_f6_val <= f6_out_pixel;
        end

        if (rst) begin
            winning_score <= -128; stream_index <= 0;
        end else if (out_out_valid) begin
            if (out_out_pixel > winning_score) begin
                winning_score <= out_out_pixel;
                winner_index <= stream_index;
            end
            if (stream_index == 9) stream_index <= 0;
            else stream_index <= stream_index + 1;
        end
    end

    // LED OUTPUT
    always_comb begin
        led = 8'b00000000;
        case (sw[2:0]) 
            3'b000: begin // RESULT
                led[3:0] = winner_index;
                led[4]   = prediction_ready;
                led[5]   = c5_done_latched;
                led[6]   = f6_done_latched;
                led[7]   = out_done_latched;
            end
            3'b001: led = peak_c1_val; // Debug C1
            3'b010: led = peak_l2_val; // Debug L2
            3'b011: led = peak_c5_val; // Debug C5
            3'b100: led = peak_f6_val; // Debug F6
            3'b101: led = winning_score; // Confidence
            3'b110: begin // RAW FLAGS
                led[0] = c1_done[0];
                led[1] = l2_weights_loaded;
                led[2] = l2_done_sig;
                led[3] = c5_done_latched;
                led[4] = f6_done_latched;
                led[5] = out_done_latched;
                led[7] = 1;
            end
            default: led = 8'b11111111;
        endcase
    end

endmodule