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
    logic signed [7:0] actual_out [TOTAL_OUTPUTS-1:0]; 
    int out_write_ptr;

    // DUT
    maxpool_engine #(.MAP_WIDTH(INPUT_DIM)) DUT (
        .clk(clk), .rst(rst),
        .valid_in(valid_in), .pixel_in(pixel_in),
        .valid_out(valid_out), .pixel_out(pixel_out), .all_done(all_done)
    );

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Robust Signed Max Function
    function automatic signed [7:0] max4(input signed [7:0] a, b, c, d);
        logic signed [7:0] m1, m2;
        m1 = ($signed(a) > $signed(b)) ? a : b;
        m2 = ($signed(c) > $signed(d)) ? c : d;
        return ($signed(m1) > $signed(m2)) ? m1 : m2;
    endfunction

    // Data Gen
    task gen_data();
        for(int r=0; r<INPUT_DIM; r++)
            for(int c=0; c<INPUT_DIM; c++)
                source_image[r][c] = $random() % 128; 

        for(int r=0; r<OUTPUT_DIM; r++) begin
            for(int c=0; c<OUTPUT_DIM; c++) begin
                expected_out[r][c] = max4(
                    source_image[r*2][c*2],     source_image[r*2][c*2+1],
                    source_image[r*2+1][c*2],   source_image[r*2+1][c*2+1]
                );
            end
        end
    endtask

    // Main Process
    initial begin
        gen_data();
        rst = 1; valid_in = 0; pixel_in = 0; out_write_ptr = 0;
        
        repeat(5) @(posedge clk);
        rst <= 0; // Use non-blocking for reset too
        repeat(2) @(posedge clk);

        $display("Starting MaxPool Stream...");

        // FEED DATA
        for (int i = 0; i < TOTAL_INPUTS; i++) begin
            @(posedge clk);
            // FIX: USE NON-BLOCKING ASSIGNMENT (<=) to avoid race conditions
            valid_in <= 1;
            pixel_in <= source_image[i / INPUT_DIM][i % INPUT_DIM];
            
            // Debug Print for Row 1 (Indices 28-35)
            // Note: Since we use <=, the value prints "what we are scheduling", which is correct
            if (i >= 28 && i <= 35) begin
               $display("TB SENDING Idx%0d: %0d", i, source_image[i / INPUT_DIM][i % INPUT_DIM]);
            end
        end

        @(posedge clk);
        valid_in <= 0;
        pixel_in <= 0;

        // Wait for Done
        fork
            begin
                wait(all_done);
                $display("Hardware signaled DONE.");
            end
            begin
                repeat(500) @(posedge clk);
                $display("ERROR: Timeout waiting for all_done!");
                $stop;
            end
        join_any
        disable fork;

        @(posedge clk);
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
        if (out_write_ptr != TOTAL_OUTPUTS) begin
            $display("ERROR: Count Mismatch. Expected %0d, got %0d", TOTAL_OUTPUTS, out_write_ptr);
            errors++;
        end

        for (int r=0; r<OUTPUT_DIM; r++) begin
            for (int c=0; c<OUTPUT_DIM; c++) begin
                int linear_addr = r * OUTPUT_DIM + c;
                if (actual_out[linear_addr] !== expected_out[r][c]) begin
                    $display("ERROR at Output [%0d][%0d] (Linear %0d)", r, c, linear_addr);
                    $display("  Expected: %0d", expected_out[r][c]);
                    $display("  Got:      %0d", actual_out[linear_addr]);
                    errors++;
                end
            end
        end

        if (errors == 0) $display("SUCCESS: All %0d pixels match!", TOTAL_OUTPUTS);
        else $display("FAILURE: %0d mismatches found.", errors);
    endtask

endmodule