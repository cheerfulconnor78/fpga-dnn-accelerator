module fpga_top_layer1 (
    input  logic clk,       // 50MHz Clock
    input  logic rst_n,     // Key 0 (Active Low)
    output logic [1:0] led  // LED 0 = Done, LED 1 = Error
);
    // 1. SETTINGS
    localparam MAPSIZE = 32;
    localparam TOTAL_PIXELS = MAPSIZE * MAPSIZE; // 1024
    
    // MaxPool reduces 28x28 -> 14x14
    localparam OUTPUT_COUNT = 14 * 14; // 196

    logic rst;
    assign rst = ~rst_n;

    // 2. MEMORIES (ROMs)
    // Image ROM: 32x32 Input (8-bit)
    (* ram_init_file = "image.mif" *)   
    logic signed [7:0]  image_rom  [0:TOTAL_PIXELS-1];

    // Golden ROM: 14x14 Expected Output (8-bit)
    // NOTE: Make sure to generate "golden_layer1.mif" from your simulation results!
    (* ramstyle = "logic", ram_init_file = "golden_layer1.mif" *) 
    logic signed [7:0] golden_rom [0:OUTPUT_COUNT-1];

    // 3. DATA FEEDER LOGIC
    logic data_valid_in;
    logic signed [7:0] pixel_in;
    
    // Read Pointer for Input Image
    logic [$clog2(TOTAL_PIXELS):0] read_ptr;
    logic start;
    
    // Outputs from DUT
    logic data_valid_out;
    logic signed [7:0] pixel_out;
    logic layer_done;

    typedef enum { IDLE, RUN, DONE } state_t;
    state_t state;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            read_ptr <= 0;
            data_valid_in <= 0;
            start <= 0;
        end else begin
            case (state)
                IDLE: begin
                    start <= 1;
                    state <= RUN;
                end

                RUN: begin
                    start <= 0;
                    if (read_ptr < TOTAL_PIXELS) begin
                        data_valid_in <= 1;
                        pixel_in <= image_rom[read_ptr[9:0]];
                        read_ptr <= read_ptr + 1;
                    end else begin
                        data_valid_in <= 0;
                        if (layer_done) state <= DONE;
                    end
                end

                DONE: begin
                    data_valid_in <= 0;
                end
            endcase
        end
    end

    // 4. DUT INSTANTIATION
    // Note: Weights are now internal to lenet_top, so we don't pass them here.
    lenet_top DUT (
        .clk(clk),
        .rst(rst),
        .start(start),
        .data_valid_in(data_valid_in),
        .pixel_in(pixel_in),
        
        // Outputs
        .data_valid_out(data_valid_out),
        .pixel_out(pixel_out),
        .layer_done(layer_done)
    );

    // 5. REAL-TIME VERIFIER
    logic error_latched;
    
    // Pointer to track position in Golden ROM
    logic [$clog2(OUTPUT_COUNT):0] check_ptr;

    always_ff @(posedge clk) begin
        if (rst) begin
            error_latched <= 0;
            check_ptr <= 0;
        end else begin
            if (data_valid_out) begin
                // Check against golden ROM
                if (pixel_out !== golden_rom[check_ptr]) begin
                    error_latched <= 1;
                end
                
                // Increment pointer to check next pixel next time
                check_ptr <= check_ptr + 1;
            end
        end
    end

    // 6. LED OUTPUTS
    // LED 0 (Green) = ON if Done.
    // LED 1 (Red)   = ON if Error.
    assign led[0] = (state == DONE); 
    assign led[1] = error_latched;   

endmodule