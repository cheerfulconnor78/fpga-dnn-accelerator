class Matrix;

    rand logic [DATA_WIDTH-1:0] A[SIZE-1:0][SIZE-1:0];
    rand logic [DATA_WIDTH-1:0] X[SIZE-1:0][SIZE-1:0];
    logic [RESULT_WIDTH-1:0] expected [SIZE-1:0][SIZE-1:0];

    constraint matrices{
        foreach (A[i,j]) {
            // A 2 in 10 chance of being zero
            A[i][j] dist { 0 := 2, [1:255] := 8 };
        }
        foreach (X[i,j]) {
            // A 2 in 10 chance of being zero
            X[i][j] dist { 0 := 2, [1:255] := 8 };
        }
    }

    function void correct();
        for(int i = 0; i < SIZE; i++) begin
            for(int j = 0; j < SIZE; j++)begin
                expected[i][j] = 0;
                for(int k = 0; k < SIZE; k++) begin
                    expected[i][j] += A[i][k] * X[k][j];
                end
            end
        end
    endfunction
endclass

module tb_rand_systolic;
localparam SIZE = 8;    
localparam DATA_WIDTH = 8;
localparam RESULT_WIDTH = 32;
localparam NUMCYCLES = 15;

logic clk;
logic rst;


logic [DATA_WIDTH-1:0] tb_row_weights[SIZE-1:0];
logic [DATA_WIDTH-1:0] tb_col_activations[SIZE-1:0];
logic [RESULT_WIDTH-1:0] res[SIZE-1:0][SIZE-1:0];

logic [DATA_WIDTH-1:0] feed_A [DATA_WIDTH-1:0][NUMCYCLES-1:0]; //8 ports 15 cycles
logic [DATA_WIDTH-1:0] feed_X [DATA_WIDTH-1:0][NUMCYCLES-1:0];
    
    
systolic DUT(
    .clk(clk),
    .rst(rst),
    .row_weights(tb_row_weights),
    .col_activations(tb_col_activations),
    .result(res)
);



int cycle;
int error_count;

initial begin
    Matrix mat;
    $display("starting randomized test");
    clk = 0;
    rst = 1;

    // Clear DUT inputs
    for (int i = 0; i < SIZE; i++) begin
        tb_row_weights[i] = 0;
        tb_col_activations[i] = 0;
    end

    repeat (10) begin
        mat = new();
        if (!mat.randomize())begin
            $fatal("transaction randomization failed");
        end
        mat.correct();
        run_test(mat);
    end
    $display("10 tests finished");
    $finish;
end

always #5 clk = ~clk;   

task run_test(input Matrix t);
    $display("running new test");
    //precalculate stagger for feed
    //1: initialize all to 0
    //2: which cycle a data goes in = i + j

    for(int i = 0; i < SIZE; i++) begin
        for(int j = 0; j < NUMCYCLES; j++) begin
            feed_A[i][j] = 0;
            feed_X[i][j] = 0;
        end
    end

    for(int i = 0; i < SIZE; i++) begin
        for(int j = 0; j < SIZE; j++) begin
            cycle = i + j;
            feed_A[i][cycle] = t.A[i][j];
            feed_X[j][cycle] = t.X[i][j];
        end
    end
    
        #20;
    rst = 0;
    //start test
    $display("reset off, starting test");
    for(int c = 0; c < NUMCYCLES; c++) begin
        @(posedge clk);
        for(int i = 0; i < SIZE; i++) begin
            tb_row_weights[i] <= feed_A[i][c];
            tb_col_activations[i] <= feed_X[i][c];
        end
    end

    //stop feed 
    @(posedge clk);
    for(int i = 0; i < SIZE; i++) begin
        tb_row_weights[i] <= 0;
        tb_col_activations[i] <= 0;
    end

    $display("feed finished");
    repeat (SIZE * 3) @(posedge clk);
    
    for(int i = 0; i < SIZE; i++) begin
        for(int j = 0; j < SIZE; j++) begin
            if(res[i][j] != t.expected[i][j])begin
                $display("!!! FAIL at [%d][%d]: Exp %d, Got %d",
                             i, j, t.expected[i][j], res[i][j]);
                error_count++;
            end
        end
    end

    if (error_count == 0) $display("--- TEST PASSED ---");
    else $display("--- TEST FAILED: %d errors ---", error_count);

    //cleanup
    rst = 1;
    #20;
endtask

endmodule