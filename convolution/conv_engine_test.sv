// constrained randomized test for full 32x32 to 28x28 convolution
module conv_test; 
    localparam SIZE = 32;
    //5x5 matrix input class that computes correct convolution
    class Matrix;
        localparam SIZE = 32;
        rand logic signed[7:0]  weights[4:0][4:0];
        rand logic signed [7:0] inputs[31:0][31:0];
        logic signed[31:0]  expected [27:0][27:0];

    // --- 1. MNIST-like Constraints ---
    constraint mnist_inputs {
        foreach(inputs[i,j]) {
            // MNIST images are "sparse" (mostly black background).
            // Weights 0 heavily (80% chance).
            // Since DUT is signed, we constrain valid pixels 0 to 127.
            inputs[i][j] dist {
                0       := 80, // Background (Black)
                [1:127] := 20  // Features (Greyscale/White)
            };
        }
    }

        function void correct();
            //initialize result to 0
            for(int i = 0; i < SIZE - 4; i++) begin
                for(int j = 0; j < SIZE - 4; j++) begin
                    expected[i][j] = 32'sb0;
                end
            end
            int x_traversal = 0;
            int y_traversal = 0;
            for(int k = 0; k < 784; k++) begin //28*28 = 783
                for(int i = 0; i < 5; i++) begin    
                    for(int j = 0; j < 5; j++) begin
                        expected[y_traversal][x_traversal] += weights[i][j]*inputs[y_traversal + i][x_traversal + j];
                    end
                end
                if(x_traversal < 27) begin
                    x_traversal = x_traversal + 1;
                end else begin //x is at limit
                    y_traversal = y_traversal + 1;
                    x_traversal = 0;
                end
            end
        endfunction
    endclass

    logic clk, rst, start, done;
    logic signed [7:0] inputs[4:0][4:0];
    logic signed[7:0]  weights[4:0][4:0];
    logic  signed [31:0]outputs;

    conv DUT(
        .clk(clk),
        .rst(rst),
        .start(start),
        .weights(weights),
        .inputs(inputs),
        .outputs(outputs),
        .done(done)
    );

    initial begin
        Matrix mat;
        $display("starting test");

        repeat (20) begin
            mat = new();
            if(!mat.randomize()) begin
                $fatal("error!");
            end
            mat.correct();
            run_test(mat);
        end
        $display("All 20 tests complete");
        $finish;
    end

    initial begin
        clk = 0;
        rst = 1;
        start = 0;
        #20;
        rst = 0;
        #10;
    end

    always #5 clk = ~clk;

 // --- Main Test Thread ---
    initial begin
        Matrix mat;
        
        // Wait for reset to finish
        wait (rst == 0);
        @(posedge clk);

        $display("Starting test...");
        
        repeat (20) begin
            mat = new();
            if(!mat.randomize()) begin
                $fatal("error!");
            end
            mat.correct(); // Calculate expected result
            run_test(mat); // Run the sequential test
        end
        
        $display("All 20 tests complete");
        $finish;
    end

    // --- Sequential Test Task ---
    task run_test(input Matrix t);
        automatic bit error_found = 0;
        $display("Running new test...");

        // 0. Wait for the DUT to be idle (done is a 1-cycle pulse)
        @(posedge clk);
        wait(done == 0);

        // 1. Drive the randomized values to the DUT's input
        //    Inputs must be stable *before* start is asserted.
        inputs = t.inputs;
        weights = t.weights;
        start <= 1'b1;

        // 2. Wait one clock cycle for 'start' to be registered
        @(posedge clk);
        start <= 1'b0; // De-assert start

        // 3. Wait for the 'done' signal (with a timeout)
        fork
            // --- Process A: Wait for 'done' ---
            begin
                @(posedge done);
                $display("  DUT reported done.");
            end
            // --- Process B: Timeout ---
            begin : timeout_block
                repeat(40) @(posedge clk); // DUT takes ~26 cycles. 40 is a safe timeout.
                $error("  [FAIL] Test TIMEOUT! DUT did not complete.");
                error_found = 1;
            end
        join_any
        disable timeout_block; // Disable the timeout if 'done' arrived

        // 4. Check the result.
        // The 'output' and 'done' signals are valid on the same cycle.
        if (!error_found) begin
            if (outputs !== t.expected) begin
                $display("  [FAIL] MISMATCH!");
                $display("  Expected: %0d (%h)", t.expected, t.expected);
                $display("  Got:      %0d (%h)", outputs, outputs);
                error_found = 1;
            end
        end

        // 5. Report the result of this single test
        if (!error_found) begin
            $display("  [PASS] Test passed.");
        end else begin
            $display("  [FAIL] Test failed.");
        end
        
        // 6. Wait for the 1-cycle 'done' pulse to go away
        @(posedge clk);

    endtask
endmodule