module lenet_channel_layer2 #(parameter CHANNEL_ID = 0)(
    input logic clk, rst, start,
    
    // External data stream
    input logic [5:0] data_valid_in,
    input logic signed [5:0][7:0] pixel_in,
    input logic [3:0] weight_id,

    // Data out
    output logic data_valid_out,
    output logic signed [7:0] pixel_out,
    output logic layer_done,
    output logic loading_done
);
    localparam MAPSIZE = 14;     
    localparam OUTPUT_SHIFT = 10;  

    // 1. WEIGHT STORAGE
    logic signed [7:0] weights [5:0][4:0][4:0]; 
    logic [7:0] rom_addr; 
    logic signed [7:0] rom_data;
    
    layer2_rom_banked weight_mem (
        .clk(clk),
        .bank_id(weight_id), // Pass the input here
        .addr(rom_addr),
        .weight_out(rom_data)
    );

   // 2. WEIGHT LOADING STATE MACHINE
    logic [7:0] load_counter; 
    (* preserve *) logic internal_loading_done;
    
    // Explicit counters for array indexing (Replaces / and %)
    logic [2:0] w_ch_cnt;
    logic [2:0] w_row_cnt;
    logic [2:0] w_col_cnt;

    // TIMING FIX: Pipeline the start signal to break the critical path
    (* preserve *) logic internal_start;

    always_ff @(posedge clk) begin
        if (rst) begin
            load_counter   <= 0;
            internal_loading_done   <= 0;
            rom_addr       <= 0;
            internal_start <= 0;
            w_ch_cnt       <= 0;
            w_row_cnt      <= 0;
            w_col_cnt      <= 0;
        end else begin
            internal_start <= (start && internal_loading_done);

            if (!internal_loading_done) begin
                // 1. REQUEST NEXT DATA
                // We always ask for the NEXT address ahead of time
                rom_addr <= load_counter + 1;

                // 2. CAPTURE CURRENT DATA (from previous request)
                // We only write when load_counter > 0 because of the 1-cycle RAM latency.
                // Fix: Stop exactly after 150 writes to prevent overwrite
                if (load_counter > 0 && load_counter <= 150) begin
                    weights[w_ch_cnt][w_row_cnt][w_col_cnt] <= rom_data;
                    
                    // Increment 3D Indices only when we actually write
                    if (w_col_cnt == 4) begin
                        w_col_cnt <= 0;
                        if (w_row_cnt == 4) begin
                            w_row_cnt <= 0;
                            if (w_ch_cnt == 5) begin
                                w_ch_cnt <= 0;
                            end else begin
                                w_ch_cnt <= w_ch_cnt + 1;
                            end
                        end else begin
                            w_row_cnt <= w_row_cnt + 1;
                        end
                    end else begin
                        w_col_cnt <= w_col_cnt + 1;
                    end
                end

                // 3. STOP CONDITION
                // 150 weights + 1 cycle for the pipeline to flush the last value
                if (load_counter == 151) begin 
                    internal_loading_done <= 1;
                end else begin
                    load_counter <= load_counter + 1;
                end
            end
        end
    end

    assign loading_done = internal_loading_done;

    // 3. CONVOLUTION ENGINES
    logic [5:0] internal_valid;
    logic [5:0][31:0] internal_data; 
    
    genvar i;
    generate
        for (i = 0; i < 6; i++) begin : parallel_conv
            conv_engine #( .MAPSIZE(MAPSIZE) ) conv (
                .clk(clk),
                .rst(rst),
                // USE THE PIPELINED SIGNAL HERE
                .start(start), 
                
                .data_valid_in(data_valid_in[i]), 
                .pixel_in(pixel_in[i]),           
                .weights(weights[i]),             
                .mem_wr_addr(), 
                .mem_wr_data(internal_data[i]),   
                .mem_wr_en(internal_valid[i]),    
                .all_done()
            );
        end
    endgenerate

    // 4. ACCUMULATION
    logic signed [31:0] channel_sum;
    logic sum_valid;
    logic conv_valid_out;

    assign sum_valid = internal_valid[0]; 
    assign conv_valid_out = sum_valid;    

    assign channel_sum = internal_data[0] + internal_data[1] + 
                         internal_data[2] + internal_data[3] + 
                         internal_data[4] + internal_data[5];

    // 5. QUANTIZATION
    logic signed [31:0] scaled_data;
    logic signed [7:0] relu_pixel_comb;

    assign scaled_data = channel_sum >>> OUTPUT_SHIFT; 

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

    // 6. MAXPOOL
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