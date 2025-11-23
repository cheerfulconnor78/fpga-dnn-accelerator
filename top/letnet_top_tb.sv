`timescale 1ns/1ps

module lenet_top_tb;
    // ------------------------------------------------
    // 1. PARAMETERS
    // ------------------------------------------------
    localparam MAPSIZE = 32;               // Input Image (32x32)
    localparam TOTAL_PIXELS = MAPSIZE * MAPSIZE; // 1024
    
    // Final Output (Conv 28x28 -> MaxPool 14x14)
    localparam OUT_DIM = 14; 
    localparam TOTAL_OUTPUTS = OUT_DIM * OUT_DIM; // 196

    // ------------------------------------------------
    // 2. SIGNALS
    // ------------------------------------------------
    logic clk, rst, start;
    
    // Inputs
    logic data_valid_in;
    logic signed [7:0] pixel_in;
    logic signed [7:0] weights [4:0][4:0];
    
    // Outputs
    logic data_valid_out;
    logic signed [7:0] pixel_out;
    logic layer_done;

    // ------------------------------------------------
    // 3. MEMORIES (Inputs & Golden Reference)
    // ------------------------------------------------
    logic signed [7:0] image_mem  [0:TOTAL_PIXELS-1];
    logic signed [7:0] golden_mem [0:TOTAL_OUTPUTS-1];

    // ------------------------------------------------
    // 4. INSTANTIATE TOP LEVEL
    // ------------------------------------------------
    lenet_top DUT (
        .clk(clk),
        .rst(rst),
        .start(start),
        .data_valid_in(data_valid_in),
        .pixel_in(pixel_in),
        .weights(weights),
        .data_valid_out(data_valid_out),
        .pixel_out(pixel_out),
        .layer_done(layer_done)
    );

    // ------------------------------------------------
    // 5. CLOCK GENERATION
    // ------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ------------------------------------------------
    // 6. SETUP & DATA LOADING
    // ------------------------------------------------
    initial begin
        // Load Hex Files (Make sure these exist!)
        // image.mem should have 1024 lines
        // golden.mem should have 196 lines (Final 14x14 output)
        $readmemh("image.mem", image_mem);
        $readmemh("golden_layer1.mem", golden_mem);
        
        // Hardcode Weights (Must match your Python script!)
        // Example: Standard LeNet Conv1 Kernel 0
        weights = '{
            '{ 0,  0, -1,  0,  0},
            '{ 0, -1, -2, -1,  0},
            '{-1, -2, 16, -2, -1},
            '{ 0, -1, -2, -1,  0},
            '{ 0,  0, -1,  0,  0}
        };
    end

    // ------------------------------------------------
    // 7. MAIN SIMULATION PROCESS
    // ------------------------------------------------
    initial begin
        // Initialize
        rst = 1; start = 0; data_valid_in = 0; pixel_in = 0;
        
        // Reset Pulse
        repeat(10) @(posedge clk);
        rst <= 0;
        
        // Start Pulse (Optional, depending on your Conv logic)
        repeat(2) @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;

        $display("--- Starting Layer 1 Processing ---");

        // Feed Data (Streaming 32x32 image)
        for(int i=0; i<TOTAL_PIXELS; i++) begin
            @(posedge clk);
            // Non-Blocking Assignments to prevent races!
            data_valid_in <= 1;
            pixel_in <= image_mem[i];
        end
        
        // Stop Stream
        @(posedge clk);
        data_valid_in <= 0;
        pixel_in <= 0;
        
        // Wait for Completion
        // We use the layer_done signal from MaxPool
        fork
            begin
                wait(layer_done);
                $display("Hardware signaled Layer DONE.");
            end
            begin
                // Timeout: 32*32 + Pipeline Latency (approx 2000 cycles safe)
                repeat(3000) @(posedge clk);
                $display("ERROR: Timeout waiting for layer_done!");
                $stop;
            end
        join_any
        disable fork;

        @(posedge clk);
        $display("Simulation Finished. Checked %0d outputs.", write_ptr);
        
        if (errors == 0 && write_ptr == TOTAL_OUTPUTS)
            $display("SUCCESS: Full Layer 1 Verified!");
        else
            $display("FAILURE: Found %0d errors.", errors);
            
        $stop;
    end

    // ------------------------------------------------
    // 8. AUTOMATIC CHECKER
    // ------------------------------------------------
    int write_ptr = 0;
    int errors = 0;

    always @(posedge clk) begin
        if (data_valid_out) begin
            // Compare DUT output vs Golden Memory
            if (pixel_out !== golden_mem[write_ptr]) begin
                $display("Error at Index %0d: Expected %d, Got %d", 
                          write_ptr, golden_mem[write_ptr], pixel_out);
                errors++;
            end
            write_ptr++;
        end
    end

endmodule