module tb_systolic;
    logic clk;
    logic rst;
    #define SIZE 8
    #define DATA_WIDTH 8
    #define RESULT_WIDTH 32
    #define NUMCYCLES 15 //data width*2-1
    //5 unit period clock
    always #5 clk = ~clk;

    logic [DATA_WIDTH-1:0] tb_row_weights[SIZE-1:0];
    logic [DATA_WIDTH-1:0] tb_col_activations[SIZE-1:0];
    logic [RESULT_WIDTH-1:0] res[SIZE-1:0][SIZE-1:0];

    //test matrices
    logic [DATA_WIDTH-1:0] test_A[SIZE-1:0][SIZE-1:0];
    logic [DATA_WIDTH-1:0] test_X[SIZE-1:0][SIZE-1:0];
    logic [DATA_WIDTH-1:0] test_corr[SIZE-1:0][SIZE-1:0];
    logic [RESULT_WIDTH-1:0] test_ans[SIZE-1:0][SIZE-1:0];

    logic [DATA_WIDTH-1:0] feed_A [DATA_WIDTH-1:0][NUMCYCLES-1:0]; //8 ports 15 cycles
    logic [DATA_WIDTH-1:0] feed_X [DATA_WIDTH-1:0][NUMCYCLES-1:0];
    
    systolic DUT(
        .clk(clk),
        .rst(rst),
        .row_weights(tb_row_weights),
        .col_activations(tb_col_activations),
        .result(res)
    )
    
    initial begin
    $display("start");
    clk = 0;
    rst = 1;
    
    // Clear DUT inputs
    for (int i = 0; i < SIZE; i++) begin
        tb_row_weights[i] = 0;
        tb_col_activations[i] = 0;
    end

    for(int i = 0; i < SIZE; i++) begin
        for(int j = 0; j < SIZE; j++) begin
            test_A[i][j] = (i==j) ? 1 : 0; //I   
            test_X[i][j] = (i==j) ? 2 : 0; //2I
            test_corr[i][j] = (i==j) ? 2 : 0;
        end 
    end

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
            int cycle = i + j;
            feed_A[i][cycle] = test_A[i][j];
            feed_X[j][cycle] = test_X[i][j];
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
    
    int error_count = 0;
    for(int i = 0; i < SIZE; i++) begin
        for(int j = 0; j < SIZE; j++) begin
            if(res[i][j] != test_corr[i][j])begin
                $display("!!! FAIL at [%d][%d]: Exp %d, Got %d",
                             i, j, test_corr[i][j], res[i][j]);
                error_count++;
            end
        end
    end

    if (error_count == 0) $display("--- TEST PASSED ---");
    else $display("--- TEST FAILED: %d errors ---", error_count);
    $finish;
endmodule