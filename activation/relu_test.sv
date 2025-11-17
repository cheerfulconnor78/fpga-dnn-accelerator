// constrained randomized test for relu array module itself
module relu_test; // Added a module name for clarity
    localparam SIZE = 8;

    class Matrix;
        rand logic[31:0] weights[7:0][7:0];
        logic [31:0] expected[7:0][7:0];

        // a 50/50 mix of positive and negative values.
        constraint matrices{
            foreach(weights[i,j]) {
                weights[i][j][31] dist {0 := 1, 1 := 1};
            }
        }

        function void correct();
            for(int i = 0; i < SIZE; i++) begin
                for(int j = 0; j < SIZE; j++) begin
                    expected[i][j] = (weights[i][j][31]) ? 32'h0 : weights[i][j];
                end
            end
        endfunction
    endclass

    logic clk, rst;
    logic[31:0] input[7:0][7:0];
    logic[31:0] output[7:0][7:0];

    relu_array DUT(
        .weights_in(input),
        .weights_out(output)
    );

    initial begin
        Matrix mat;
        $display("starting test");

        repeat (20) begin
            mat = new();
            if(!mat.randomize()) begin [cite: 9]
                $fatal("error!"); [cite: 10]
            end
            mat.correct();
            run_test(mat);
        end
        $display("All 20 tests complete");
        $finish;
    end

    always #5 clk = ~clk; [cite: 11]

    task run_test(input Matrix t);
        bit error_found = 0;
        $display("Running new test...");

        // 1. Drive the randomized values to the DUT's input
        input = t.weights;

        // 2. Wait for the combinational logic to propagate.
        // #1 is sufficient since the DUT is purely combinational.
        #1;

        // 3. Check every output element against the expected value
        for(int i = 0; i < SIZE; i++) begin
            for(int j = 0; j < SIZE; j++) begin
                if (output[i][j] !== t.expected[i][j]) begin
                    $display("  [FAIL] MISMATCH! @ index [%0d][%0d]", i, j);
                    $display("    Input:    %h (%d)", t.weights[i][j], t.weights[i][j]);
                    $display("    Expected: %h (%d)", t.expected[i][j], t.expected[i][j]);
                    $display("    Got:      %h (%d)", output[i][j], output[i][j]);
                    error_found = 1;
                end
            end
        end

        // 4. Report the result of this single test
        if (!error_found) begin
            $display("  [PASS] Test passed.");
        end else begin
            $display("  [FAIL] Test failed.");
        end
    endtask
endmodule