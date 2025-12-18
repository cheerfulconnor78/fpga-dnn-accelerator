module fpga_top_layer1 (
    input  logic clk,       // 50MHz Clock
    input  logic rst_n,     // Key 0 (Active Low)
    output logic [7:0] led  // 8 LEDs for Status/Debug
);
    // 1. SETTINGS
    localparam MAPSIZE = 32;
    localparam TOTAL_PIXELS = MAPSIZE * MAPSIZE; // 1024
    localparam OUTPUT_COUNT = 5*5; // 25

    logic rst;
    assign rst = ~rst_n;

    // 2. MEMORIES (Restored to MIFs)
    // We force "logic" style so reads are Instant (Combinational).
    // This prevents the timing mismatch between hardware and simulation.
    
    (* ramstyle = "logic", ram_init_file = "image.mif" *)   
    logic signed [7:0]  image_rom  [0:TOTAL_PIXELS-1];

    (* ramstyle = "logic", ram_init_file = "golden_layer2.mif" *) 
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

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            read_ptr <= 0;
            data_valid_in <= 0;
            start <= 0;
            pixel_in <= 0;
            startup_timer <= 0;
        end else begin
            case (state)
                IDLE: begin
                    state <= WAIT_LOAD;
                end

                // NEW STATE: Wait for internal weight loading to finish
                WAIT_LOAD: begin
                    start <= 0;
                    if (startup_timer == 60) begin
                        start <= 1; // Pulse start to trigger the loaders
                        state <= RUN;
                    end else begin
                        startup_timer <= startup_timer + 1;
                    end
                end

                RUN: begin
                    // (This logic remains exactly the same as your source lines 48-52)
                    if (read_ptr < TOTAL_PIXELS) begin
                        data_valid_in <= 1;
                        pixel_in <= image_rom[read_ptr];
                        read_ptr <= read_ptr + 1;
                    end else begin
                        data_valid_in <= 0;
                        // Check if ALL layers are done (using the array)
                        if (layer_done) state <= DONE; 
                    end
                end

                DONE: begin
                    data_valid_in <= 0;
                end
            endcase
        end
    end

    // 4. DUT INSTANTIATION (Modified for Parallel)
    
    // Intermediate wires for the 6 parallel channels of c1
    logic [5:0] c1_valid_out;
    logic [5:0][7:0] c1_pixel_out;
    logic [5:0] c1_done;

    lenet_top_parallel DUT (
        .clk(clk), 
        .rst(rst), 
        .start(start),
        .data_valid_in(data_valid_in), 
        .pixel_in(pixel_in),
        
        // Connect the arrays
        .data_valid_out(c1_valid_out), 
        .pixel_out(c1_pixel_out),
        .layer_done(c1_done)
    );

    // --- INSTANTIATE LAYER 2 (16 Parallel Blocks) ---
    logic [15:0]       c3_valid_out;
    logic [15:0][7:0]  c3_pixel_out;
    logic [15:0]       c3_done;

    genvar i;
    generate
        for (i = 0; i < 16; i++) begin : layer2_instances
            lenet_channel_layer2 #(
                .CHANNEL_ID(i) // Loads weights_c2_0.hex, _1.hex, etc.
            ) u_l2 (
                .clk(clk),
                .rst(rst),
                
                // Actually, just pass the 'start' signal. The data_valid lines handle the timing.
                .start(start), 
                
                // CONNECT ALL 6 L1 OUTPUTS TO THIS L2 INSTANCE
                .data_valid_in(c1_valid_out), 
                .pixel_in(c1_pixel_out),
                
                // Output 1 stream per instance
                .data_valid_out(c3_valid_out[i]),
                .pixel_out(c3_pixel_out[i]),
                .layer_done(c3_done[i])
            );
        end
    endgenerate

    // MUX: Route Channel 0 to your existing Verification Logic
    assign data_valid_out = c3_valid_out[0];
    assign pixel_out      = c3_pixel_out[0];
    assign layer_done     = c3_done[0];    // Only finish when Channel 0 finishes

    // 5. VERIFIER (Trap & Display)
    logic error_latched;
    logic [$clog2(OUTPUT_COUNT):0] check_ptr;
    logic [7:0] debug_value; 

    always_ff @(posedge clk) begin
        if (rst) begin
            error_latched <= 0;
            check_ptr <= 0;
            debug_value <= 0;
        end else begin
            if (data_valid_out && !error_latched) begin
                // Check against the MIF-sourced Golden ROM
                if (pixel_out !== golden_rom[check_ptr]) begin
                    error_latched <= 1;
                    debug_value <= pixel_out; 
                end
                check_ptr <= check_ptr + 1;
            end
        end
    end

    // 6. LED OUTPUTS
    always_comb begin
        if (state == DONE && !error_latched) begin
            led = 8'hAA; // SUCCESS! (Alternating)
        end else if (error_latched) begin
            led[7]   = 1'b1; // Top bit ON = Error
            led[6:0] = debug_value[6:0]; // Show the calculated value
        end else begin
            led = read_ptr[7:0];
        end
    end
endmodule