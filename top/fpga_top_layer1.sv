module fpga_top_layer1 (
    input  logic clk,       // 50MHz Clock
    input  logic rst_n,     // Key 0 (Active Low)
    output logic [7:0] led  // 8 LEDs for Status/Debug
);
    // 1. SETTINGS
    localparam MAPSIZE = 32;
    localparam TOTAL_PIXELS = MAPSIZE * MAPSIZE; // 1024
    localparam OUTPUT_COUNT = 14 * 14; // 196

    logic rst;
    assign rst = ~rst_n;

    // 2. MEMORIES (Restored to MIFs)
    // We force "logic" style so reads are Instant (Combinational).
    // This prevents the timing mismatch between hardware and simulation.
    
    (* ramstyle = "logic", ram_init_file = "image.mif" *)   
    logic signed [7:0]  image_rom  [0:TOTAL_PIXELS-1];

    (* ramstyle = "logic", ram_init_file = "golden_layer1.mif" *) 
    logic signed [7:0] golden_rom [0:OUTPUT_COUNT-1];

    // 3. STATE MACHINE & DATA FEEDER
    logic data_valid_in;
    logic signed [7:0] pixel_in;
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
            pixel_in <= 0;
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
                        // Direct Array Read (MIF sourced)
                        pixel_in <= image_rom[read_ptr]; 
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
    lenet_top DUT (
        .clk(clk), .rst(rst), .start(start),
        .data_valid_in(data_valid_in), .pixel_in(pixel_in),
        .data_valid_out(data_valid_out), .pixel_out(pixel_out),
        .layer_done(layer_done)
    );

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
            led = 8'h00; // Running
        end
    end

endmodule