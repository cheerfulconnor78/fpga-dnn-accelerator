module conv_test; 
    localparam SIZE = 32;

    class Matrix;
        localparam SIZE = 32;
        rand logic signed[7:0]  weights[4:0][4:0];
        rand logic signed [7:0] inputs[31:0][31:0];
        logic signed[31:0]  expected [27:0][27:0];

        //MNIST-like constraints
        constraint mnist_inputs {
            foreach(inputs[i,j]) {
                inputs[i][j] dist {
                    0       := 80, // background
                    [1:127] := 20  // features
                };
            }
        }

        function void correct();
            //Initialize result to 0
            for(int i = 0; i < 28; i++) begin
                for(int j = 0; j < 28; j++) begin
                    expected[i][j] = 32'sb0;
                end
            end

            //Compute Golden Model
            for(int y = 0; y < 28; y++) begin 
                for(int x = 0; x < 28; x++) begin    
                    for(int i = 0; i < 5; i++) begin
                        for(int j = 0; j < 5; j++) begin
                            expected[y][x] += weights[i][j] * inputs[y+i][x+j];
                        end
                    end
                end
            end
        endfunction
    endclass

    logic clk, rst;
    logic done; // Connects to all_done
    
    logic signed [7:0]  features[31:0][31:0];
    logic signed [7:0]  weights[4:0][4:0];
    logic signed [31:0] outputs[27:0][27:0];


    conv_control DUT(
        .clk(clk),
        .rst(rst),
        .feature(features), 
        .weights(weights),
        .outputs(outputs),
        .all_done(done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    //main test block
    initial begin
        Matrix mat;
        
        rst = 1;
        
        $display("Starting constrained random test...");
        
        repeat (20) begin
            mat = new();
            if(!mat.randomize()) begin
                $fatal("Randomization error!");
            end
            mat.correct(); //Calculate expected results
            
            run_test(mat); //Run the sequential test
        end
        
        $display("All 20 tests complete");
        $finish;
    end

    //Sequential test task
    task run_test(input Matrix t);
        automatic bit error_found = 0;
        $display("Running new test...");

        // 1. Apply Reset and Inputs
        // The DUT loads inputs continuously, but state machine resets on RST
        rst = 1;
        features = t.inputs;
        weights  = t.weights;
        
        @(posedge clk);
        #1; 
        
        // 2. Release Reset to Start DUT
        // DUT state goes INIT -> PROCESSING immediately on rst low
        rst = 0; 

        // 3. Wait for 'done'   
        fork
            // --- Process A: Wait for completion ---
            begin
                @(posedge done);
                @(posedge clk); 
            end
            
            // --- Process B: Timeout ---
            begin : timeout_block
                // CALCULATION: 28*28 pixels = 784 operations. 
                // If each sub-conv takes ~25 cycles, we need ~19,600 cycles.
                // Using 200,000 cycles for safety
                repeat(200000) @(posedge clk);
                $error("  [FAIL] Test TIMEOUT! DUT did not complete.");
                error_found = 1;
            end
        join_any
        disable timeout_block; // Stop the timer if done triggers first

        if (!error_found) begin
            if (outputs !== t.expected) begin
                $display("  [FAIL] MISMATCH!");
                foreach(t.expected[i,j]) begin
                    if(outputs[i][j] !== t.expected[i][j]) begin
                        $display("  First mismatch at [%0d][%0d]", i, j);
                        $display("  Expected: %0d", t.expected[i][j]);
                        $display("  Got:      %0d", outputs[i][j]);
                        break; 
                    end
                end
                error_found = 1;
            end
        end

        if (!error_found) begin
            $display("  [PASS] Test passed.");
        end else begin
            $display("  [FAIL] Test failed.");
        end
        
        @(posedge clk);
        rst = 1;
    endtask
endmodule