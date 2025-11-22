module conv_file_tb;
    localparam MAPSIZE = 32;
    localparam TOTAL_PIXELS = MAPSIZE * MAPSIZE;
    localparam OUTPUT_COUNT = (MAPSIZE-4) * (MAPSIZE-4);

    logic clk, rst, start;
    logic data_valid_in;
    logic signed [7:0] pixel_in;
    logic signed [7:0] weights [4:0][4:0];
    logic [$clog2(OUTPUT_COUNT)-1:0] mem_wr_addr;
    logic signed [31:0] mem_wr_data;
    logic mem_wr_en;
    logic all_done;

    // Memories
    logic signed [7:0]  image_mem  [0:TOTAL_PIXELS-1];
    logic signed [31:0] golden_mem [0:OUTPUT_COUNT-1];

    // Instantiate DUT
    conv_engine #( .MAPSIZE(MAPSIZE) ) DUT (
        .clk(clk), .rst(rst), .start(start),
        .data_valid_in(data_valid_in), .pixel_in(pixel_in),
        .weights(weights),
        .mem_wr_addr(mem_wr_addr), .mem_wr_data(mem_wr_data),
        .mem_wr_en(mem_wr_en), .all_done(all_done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Load Files
    initial begin
        $readmemh("image.mem", image_mem);
        $readmemh("golden.mem", golden_mem);
        
        // Initialize Weights (Must match Python!)
        weights = '{
            '{ 0,  0, -1,  0,  0},
            '{ 0, -1, -2, -1,  0},
            '{-1, -2, 16, -2, -1},
            '{ 0, -1, -2, -1,  0},
            '{ 0,  0, -1,  0,  0}
        };
    end

    initial begin
        rst = 1; start = 0; data_valid_in = 0; pixel_in = 0;
        repeat(10) @(posedge clk);
        rst = 0; start = 1;
        @(posedge clk);
        start = 0;

        // Feed Data
        for(int i=0; i<TOTAL_PIXELS; i++) begin
            @(posedge clk);
            data_valid_in = 1;
            pixel_in = image_mem[i];
        end
        
        @(posedge clk);
        data_valid_in = 0;
        
        wait(all_done);
        repeat(10) @(posedge clk);
        $display("Simulation Finished. Checking...");
        $finish;
    end

    // Checker
    int errors = 0;
    always @(posedge clk) begin
        if (mem_wr_en) begin
            if (mem_wr_data !== golden_mem[mem_wr_addr]) begin
                $display("Error at Addr %0d: Expected %h, Got %h", mem_wr_addr, golden_mem[mem_wr_addr], mem_wr_data);
                errors++;
            end
        end
    end

endmodule
