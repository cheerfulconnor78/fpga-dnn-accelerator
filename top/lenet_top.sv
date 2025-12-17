module lenet_channel #(parameter CHANNEL_ID = 0 // to distinguish top level channels
)(
    input logic clk, rst, start,
    
    // external data stream
    input logic data_valid_in,
    input logic signed [7:0] pixel_in,

    // data out
    output logic data_valid_out,
    output logic signed [7:0] pixel_out,
    output logic layer_done
);

    localparam MAPSIZE = 32;     
    localparam OUTPUT_SHIFT = 8;  //log2(weights max scale)
    // 1. WEIGHT LOADING LOGIC
    // ---------------------------------------------------------
    logic signed [7:0] weights [4:0][4:0]; // The storage for the engine
    // ROM Signals
    logic [4:0] rom_addr;
    logic signed [7:0] rom_data;
    
    // Instantiate your new ROM
    layer1_weight_rom #(.CHANNEL_ID(CHANNEL_ID)) weight_mem (
        .clk(clk),
        .addr(rom_addr),
        .weight_out(rom_data)
    );

    // Loader State Machine
    // This runs once at reset to copy ROM -> Registers
    logic [4:0] load_counter;
    logic loading_done;

    always_ff @(posedge clk) begin
        if (rst) begin
            load_counter <= 0;
            loading_done <= 0;
            rom_addr <= 0;
            // Clear weights
            for (int r=0; r<5; r++) 
                for (int c=0; c<5; c++) 
                    weights[r][c] <= 0;
        end else begin
            if (!loading_done) begin
                // Pipeline delay: Address set in cycle N, Data ready in N+1
                rom_addr <= load_counter + 1; 
                
                // Store the PREVIOUS cycle's requested data
                // Map linear counter 0..24 to [row][col]
                // (This assumes your HEX file is row-major: row0, then row1...)
                if (load_counter > 0) begin
                   weights[(load_counter-1)/5][(load_counter-1)%5] <= rom_data;
                end

                if (load_counter == 26) begin // 25 weights + latency
                    loading_done <= 1;
                end else begin
                    load_counter <= load_counter + 1;
                end
            end
        end
    end

    // 2. CONVOLUTION INSTANCE
    logic conv_valid_out;
    logic signed [31:0] conv_data_out;
    logic conv_done_unused;
    logic [$clog2((MAPSIZE-4)*(MAPSIZE-4))-1:0] conv_addr_unused;

    conv_engine #( .MAPSIZE(MAPSIZE) ) conv (
        .clk(clk),
        .rst(rst),
        .start(start && loading_done),
        .data_valid_in(data_valid_in),
        .pixel_in(pixel_in),
        .weights(weights),
        .mem_wr_addr(conv_addr_unused),
        .mem_wr_data(conv_data_out),
        .mem_wr_en(conv_valid_out),
        .all_done(conv_done_unused)
    );

    // 3. QUANTIZATION LOGIC (Combinational)
    logic signed [31:0] scaled_data;
    logic signed [7:0] relu_pixel_comb;
    
    assign scaled_data = conv_data_out >>> OUTPUT_SHIFT; 

    always_comb begin
        if (scaled_data < 0) 
            relu_pixel_comb = 8'd0;
        else if (scaled_data > 127) 
            relu_pixel_comb = 8'd127;
        else 
            relu_pixel_comb = scaled_data[7:0];
    end

    // Pipeline Stage
    logic signed [7:0] relu_pixel_reg;
    logic conv_valid_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            conv_valid_reg <= 0;
            relu_pixel_reg <= 0;
        end else begin
            conv_valid_reg <= conv_valid_out;
            relu_pixel_reg <= relu_pixel_comb;
        end
    end

    // 5. MAXPOOL INSTANCE
    // Connected to the REGISTERED signals, not the combinational ones
    maxpool_engine #(.MAP_WIDTH(MAPSIZE-4)) pool (
        .clk(clk),
        .rst(rst),
        .valid_in(conv_valid_reg),  
        .pixel_in(relu_pixel_reg),   
        .valid_out(data_valid_out),
        .pixel_out(pixel_out),
        .all_done(layer_done)
    );

endmodule