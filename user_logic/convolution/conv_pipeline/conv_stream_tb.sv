module conv_stream_tb;
    // Parameters matching your design
    localparam MAPSIZE = 32;
    localparam TOTAL_PIXELS = MAPSIZE * MAPSIZE;
    localparam OUTPUT_DIM = MAPSIZE - 4;
    
    // DUT Signals
    logic clk, rst, start;
    logic data_valid_in;
    logic signed [7:0] pixel_in;
    logic signed [7:0] weights [4:0][4:0];
    
    logic [$clog2(OUTPUT_DIM*OUTPUT_DIM)-1:0] mem_wr_addr;
    logic signed [31:0] mem_wr_data;
    logic mem_wr_en;
    logic all_done;

    // Test Bench Memory
    logic signed [7:0]  source_image [MAPSIZE-1:0][MAPSIZE-1:0];
    logic signed [31:0] expected_out [OUTPUT_DIM-1:0][OUTPUT_DIM-1:0];
    logic signed [31:0] actual_out   [OUTPUT_DIM*OUTPUT_DIM-1:0]; // Linear memory to capture output

    // Instantiate DUT
    conv_engine #(
        .MAPSIZE(MAPSIZE)
    ) DUT (
        .clk(clk),
        .rst(rst),
        .start(start),
        .data_valid_in(data_valid_in),
        .pixel_in(pixel_in),
        .weights(weights),
        .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data),
        .mem_wr_en(mem_wr_en),
        .all_done(all_done)
    );

    // Clock Generation
    initial clk = 0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // TASK: Generate Random Data & Golden Model
    // ------------------------------------------------------------
    task gen_data();
        // 1. Randomize Weights
        for(int r=0; r<5; r++)
            for(int c=0; c<5; c++)
                weights[r][c] = $random() % 10; // Keep small to avoid overflow debug

        // 2. Randomize Image
        for(int r=0; r<MAPSIZE; r++)
            for(int c=0; c<MAPSIZE; c++)
                source_image[r][c] = $random() % 128;

        // 3. Calculate Golden Output
        for(int r=0; r<OUTPUT_DIM; r++) begin
            for(int c=0; c<OUTPUT_DIM; c++) begin
                expected_out[r][c] = 0;
                for(int i=0; i<5; i++) begin
                    for(int j=0; j<5; j++) begin
                        expected_out[r][c] += source_image[r+i][c+j] * weights[i][j];
                    end
                end
            end
        end
    endtask

    // ------------------------------------------------------------
    // MAIN TEST PROCESS
    // ------------------------------------------------------------
    initial begin
        gen_data();
        
        // Reset
        rst = 1; start = 0; data_valid_in = 0; pixel_in = 0;
        repeat(5) @(posedge clk);
        rst = 0; 
        repeat(2) @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        $display("Starting Stream...");

        // STREAMING LOOP
        // We feed pixels one by one, just like the hardware would
        for (int i = 0; i < TOTAL_PIXELS; i++) begin
            @(posedge clk);
            data_valid_in = 1;
            // Flatten 2D array to 1D stream
            pixel_in = source_image[i / MAPSIZE][i % MAPSIZE];
        end

        // Stop Stream
        @(posedge clk);
        data_valid_in = 0;
        pixel_in = 0;

        // Wait for done
        wait(all_done);
        $display("DUT finished. Verifying...");

        // ------------------------------------------------------------
        // VERIFICATION
        // ------------------------------------------------------------
        check_results();
        $stop;
    end

    // Capture Output
    always @(posedge clk) begin
        if (mem_wr_en) begin
            actual_out[mem_wr_addr] = mem_wr_data;
            $display("Write at Addr %0d: %0d", mem_wr_addr, mem_wr_data);
        end
    end

    task automatic check_results();
        int errors = 0;
        for (int r=0; r<OUTPUT_DIM; r++) begin
            for (int c=0; c<OUTPUT_DIM; c++) begin
                // Convert 2D Coordinate to Linear Address
                int linear_addr = r * OUTPUT_DIM + c;
                
                if (actual_out[linear_addr] !== expected_out[r][c]) begin
                    $display("ERROR at [%0d][%0d] (Addr %0d)", r, c, linear_addr);
                    $display("  Expected: %0d", expected_out[r][c]);
                    $display("  Got:      %0d", actual_out[linear_addr]);
                    errors++;
                end
            end
        end
        if (errors == 0) $display("SUCCESS: All %0d pixels match!", OUTPUT_DIM*OUTPUT_DIM);
        else $display("FAILURE: %0d mismatches found.", errors);
    endtask

endmodule