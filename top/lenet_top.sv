//top level wrapper
module lenet_top (
    input logic clk, rst, start,
    // external data stream (into convolution)
    input logic data_valid_in,
    input logic signed [7:0] pixel_in,
    input logic signed [7:0] weights [4:0][4:0],

    // data out (from maxpool)
    output logic data_valid_out,
    output logic signed [7:0] pixel_out,
    output logic layer_done
);
    localparam MAPSIZE = 32;
    //PARAMETER: QUANTIZATION SHIFT
    // IF RESULT NN IS TOO CLIPPED, INCREASE
    // IF RESULT IS  TOO DARK, DECREASE
    localparam OUTPUT_SHIFT = 0;

    logic conv_valid_out;
    logic signed [31:0] conv_data_out;
    logic conv_done_unused;
    logic [$clog2((MAPSIZE-4)*(MAPSIZE-4))-1:0] conv_addr_unused;
    conv_engine #( .MAPSIZE(32) ) conv (
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

    //ReLU + quantization logic
    logic signed [31:0] scaled_data;
    assign scaled_data = conv_data_out >>> OUTPUT_SHIFT; //ARITHMETIC SHIFT
    logic signed [7:0] relu_pixel;
    always_comb begin
        if (scaled_data < 0) begin
            relu_pixel = 8'd0;
        end else if (scaled_data >127) begin
            relu_pixel = 8'd127;
        end else begin
            relu_pixel = scaled_data[7:0];
        end
    end

    maxpool_engine #(.MAP_WIDTH(MAPSIZE-4)) pool (
        .clk(clk),
        .rst(rst),
        .valid_in(conv_valid_out),
        .pixel_in(relu_pixel),
        .valid_out(data_valid_out),
        .pixel_out(pixel_out),
        .all_done(layer_done)
    );

endmodule