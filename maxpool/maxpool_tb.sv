`timescale 1ns/1ps

module maxpool_stream_tb;
    localparam INPUT_DIM = 28; 
    localparam OUTPUT_DIM = INPUT_DIM / 2; 
    
    localparam TOTAL_INPUTS  = INPUT_DIM * INPUT_DIM;
    localparam TOTAL_OUTPUTS = OUTPUT_DIM * OUTPUT_DIM;

    // Signals
    logic clk, rst;
    logic valid_in;
    logic signed [7:0] pixel_in;
    
    logic valid_out;
    logic signed [7:0] pixel_out;
    logic all_done;

    // Memory
    logic signed [7:0] source_image [INPUT_DIM-1:0][INPUT_DIM-1:0];
    logic signed [7:0] expected_out [OUTPUT_DIM-1:0][OUTPUT_DIM-1:0];
    
    // Capture buffer
    logic signed [7:0] actual_out [TOTAL_OUTPUTS-1:0]; 
    int out_write_ptr;

    maxpool_engine #(
        .MAP_WIDTH(INPUT_DIM)
    ) DUT (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .pixel_in(pixel_in),
        .valid_out(valid_out),
        .pixel_out(pixel_out),
        .all_done(all_done)
    );

    // Clock gen
    initial clk = 0;
    always #5 clk = ~clk;
    
    // -----------------------------------------------------------
    // FIX 1: Robust Signed Comparator
    // Forces the TB to treat inputs as signed, matching the DUT logic.
    // -----------------------------------------------------------
    function automatic signed [7:0] max4(input signed [7:0] a, b, c, d);
        logic signed [7:0] m1, m2;
        m1 = ($signed(a) > $signed(b)) ? a : b;
        m2 = ($signed(c) > $signed(d)) ? c : d;
        return ($signed(m1) > $signed(m2)) ? m1 : m2;
    endfunction

    // Randomize inputs and generate golden reference
    task gen_data();
        for(int r=0; r<INPUT_DIM; r++)
            for(int c=0; c<INPUT_DIM; c++)
                source_image[r][c] = $random() % 128; 

        // Golden model 
        for(int r=0; r<OUTPUT_DIM; r++) begin
            for(int c=0; c<OUTPUT_DIM; c++) begin
                expected_out[r][c] = max4(
                    source_image[r*2][c*2],     source_image[r*2][c*2+1],
                    source_image[r*2+1][c*2],   source_image[r*2+1][c*2+1]
                );
            end
        end
    endtask

    // Main
    initial begin
        // Setup
        gen_data();
        rst = 1; valid_in = 0; pixel_in = 0; out_write_ptr = 0;
        
        // Reset
        repeat(5) @(posedge clk);
        rst = 0; 
        repeat(2) @(posedge clk);

        $display("Starting MaxPool Stream...");

        // Feed 1 pixel per cycle
        for (int i = 0; i < TOTAL_INPUTS; i++) begin
            @(posedge clk);
            valid_in = 1;
            pixel_in = source_image[i / INPUT_DIM][i % INPUT_DIM];
            
            // -----------------------------------------------------------
            // FIX 2: Debug Tracing
            // Verify the data for Output #1 (Row 0/1, Col 2/3) matches expectations
            // Indices: (0,2)=2, (0,3)=3, (1,2)=30, (1,3)=31
            // -----------------------------------------------------------
            if (i == 2 || i == 3 || i == 30 || i == 31) begin
                $display("TB SENDING [Index %0d]: %0d", i, pixel_in);
            end
        end

        // Stop Input Stream
        @(posedge clk);
        valid_in = 0;
        pixel_in = 0;

        // Wait for hardware signal
        fork
            begin
                wait(all_done);
                $display("Hardware signaled DONE.");
            end
            begin
                // Timeout failsafe
                repeat(500) @(posedge clk);
                $display("ERROR: Timeout waiting for all_done!");
                $stop;
            end
        join_any
        disable fork;

        @(posedge clk);
        
        // Verify results
        $display("DUT finished. Captured %0d samples.", out_write_ptr);
        check_results();
        $stop;
    end

    // Capture Output
    always @(posedge clk) begin
        if (valid_out) begin
            actual_out[out_write_ptr] = pixel_out;
            out_write_ptr++;
        end
    end

    // Checker
    task automatic check_results();
        int errors = 0;
        
        // Check for # of pixels
        if (out_write_ptr != TOTAL_OUTPUTS) begin
            $display("ERROR: Count Mismatch. Expected %0d items, got %0d", TOTAL_OUTPUTS, out_write_ptr);
            errors++;
        end

        // Check for data match 
        for (int r=0; r<OUTPUT_DIM; r++) begin
            for (int c=0; c<OUTPUT_DIM; c++) begin
                int linear_addr = r * OUTPUT_DIM + c;
                
                // Explicit strict equality check
                if (actual_out[linear_addr] !== expected_out[r][c]) begin
                    $display("ERROR at Output [%0d][%0d] (Linear %0d)", r, c, linear_addr);
                    $display("  Expected: %0d", expected_out[r][c]);
                    $display("  Got:      %0d", actual_out[linear_addr]);
                    errors++;
                end
            end
        end

        if (errors == 0) 
            $display("SUCCESS: All %0d pixels match!", TOTAL_OUTPUTS);
        else 
            $display("FAILURE: %0d mismatches found.", errors);
    endtask

endmodule