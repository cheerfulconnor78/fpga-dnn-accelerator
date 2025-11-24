module lenet_top (
    input logic clk, rst, start,
    
    // external data stream
    input logic data_valid_in,
    input logic signed [7:0] pixel_in,

    // data out
    output logic data_valid_out,
    output logic signed [7:0] pixel_out,
    output logic layer_done
);
    // 1. PARAMETERS & HARDCODED WEIGHTS
    localparam MAPSIZE = 32;
    localparam OUTPUT_SHIFT = 0;

    logic signed [7:0] weights [4:0][4:0];
    always_comb begin
        weights[0][0] = 0;  weights[0][1] = 0;  weights[0][2] = -1; weights[0][3] = 0;  weights[0][4] = 0;
        weights[1][0] = 0;  weights[1][1] = -1; weights[1][2] = -2; weights[1][3] = -1; weights[1][4] = 0;
        weights[2][0] = -1; weights[2][1] = -2; weights[2][2] = 16; weights[2][3] = -2; weights[2][4] = -1;
        weights[3][0] = 0;  weights[3][1] = -1; weights[3][2] = -2; weights[3][3] = -1; weights[3][4] = 0;
        weights[4][0] = 0;  weights[4][1] = 0;  weights[4][2] = -1; weights[4][3] = 0;  weights[4][4] = 0;
    end

    // 2. CONVOLUTION INSTANCE
    logic conv_valid_out;
    logic signed [31:0] conv_data_out;
    logic conv_done_unused;
    logic [$clog2((MAPSIZE-4)*(MAPSIZE-4))-1:0] conv_addr_unused;

    conv_engine #( .MAPSIZE(MAPSIZE) ) conv (
        .clk(clk),
        .rst(rst),
        .start(start),
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