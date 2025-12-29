module fpga_top (
    input  logic clk,       // 50MHz Clock
    input  logic rst_n,     // Key 0 (Active Low)
    output logic [1:0] led  // LED 0 = Done, LED 1 = Error
);

    // 1. SETTINGS
    localparam MAPSIZE = 32;
    localparam TOTAL_PIXELS = MAPSIZE * MAPSIZE; // 1024
    localparam OUTPUT_COUNT = (MAPSIZE-4) * (MAPSIZE-4);

    logic rst;
    assign rst = ~rst_n;

    // 2. MEMORIES (ROMs)
    // Quartus will infer ROMs from these arrays via the attributes
    (* ram_init_file = "image.mif" *)   logic signed [7:0]  image_rom  [0:TOTAL_PIXELS-1];
    
    // Note: Quartus infers 1024 depth for this because of 10-bit address, warning is expected.
    (* ram_init_file = "golden.mif" *)  logic signed [31:0] golden_rom [0:OUTPUT_COUNT-1];

    // 3. HARDCODED WEIGHTS (Fixed for Synthesis)
    logic signed [7:0] weights [4:0][4:0];
    
    // Use always_comb instead of initial for synthesis
    always_comb begin
        weights = '{
            '{ 0,  0, -1,  0,  0},
            '{ 0, -1, -2, -1,  0},
            '{-1, -2, 16, -2, -1},
            '{ 0, -1, -2, -1,  0},
            '{ 0,  0, -1,  0,  0}
        };
    end

    // 4. DATA FEEDER LOGIC
    logic data_valid_in;
    logic signed [7:0] pixel_in;
    
    // FIX: Added +1 to width to allow storing '1024' without overflowing to 0
    logic [$clog2(TOTAL_PIXELS):0] read_ptr; 
    
    logic start;
    logic engine_done;

    // Engine Output Signals
    logic [$clog2(OUTPUT_COUNT)-1:0] mem_wr_addr;
    logic signed [31:0] mem_wr_data;
    logic mem_wr_en;

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
                    
                    // This logic now works because read_ptr can hold 1024
                    if (read_ptr < TOTAL_PIXELS) begin
                        data_valid_in <= 1;
                        pixel_in <= image_rom[read_ptr[9:0]]; // Cast index to avoid warnings
                        read_ptr <= read_ptr + 1;
                    end else begin
                        // This block is now reachable!
                        data_valid_in <= 0;
                        if (engine_done) state <= DONE;
                    end
                end

                DONE: begin
                    data_valid_in <= 0;
                end
            endcase
        end
    end

    // 5. DUT INSTANTIATION
    conv_engine #( .MAPSIZE(MAPSIZE) ) DUT (
        .clk(clk),
        .rst(rst),
        .start(start),
        .data_valid_in(data_valid_in),
        .pixel_in(pixel_in),
        .weights(weights),
        .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data),
        .mem_wr_en(mem_wr_en),
        .all_done(engine_done)
    );

    // 6. REAL-TIME VERIFIER
    logic error_latched;
    always_ff @(posedge clk) begin
        if (rst) begin
            error_latched <= 0;
        end else begin
            if (mem_wr_en) begin
                // Check against golden ROM
                if (mem_wr_data !== golden_rom[mem_wr_addr]) begin
                    error_latched <= 1;
                end
            end
        end
    end

    // 7. LED OUTPUTS
    // LED 0 (Green) = ON if Done. LED 1 (Red) = ON if Error.
    assign led[0] = (state == DONE); 
    assign led[1] = error_latched;   

endmodule