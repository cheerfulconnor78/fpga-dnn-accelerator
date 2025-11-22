module conv_pipelined (
    input logic clk,
    input logic signed [7:0] window [4:0][4:0],
    input logic signed [7:0] weights [4:0][4:0],
    output logic signed [31:0] result
);
    // Stage 1: Products
    logic signed [15:0] products [4:0][4:0];
    
    // Stage 2: Row Sums
    logic signed [19:0] row_sums [4:0];
    
    // Stage 3: Final Result
    logic signed [31:0] final_sum;

    always_ff @(posedge clk) begin
        // --- STAGE 1: MULTIPLY ---
        for(int i=0; i<5; i++) begin
            for(int j=0; j<5; j++) begin
                products[i][j] <= window[i][j] * weights[i][j];
            end
        end

        // --- STAGE 2: ADD ROWS (Manual Sign Extension) ---
        // We manually repeat the sign bit [15] 4 times to extend 16->20 bits.
        for(int i=0; i<5; i++) begin
            row_sums[i] <= 
                { {4{products[i][0][15]}}, products[i][0] } + 
                { {4{products[i][1][15]}}, products[i][1] } + 
                { {4{products[i][2][15]}}, products[i][2] } + 
                { {4{products[i][3][15]}}, products[i][3] } + 
                { {4{products[i][4][15]}}, products[i][4] };
        end

        // --- STAGE 3: FINAL ACCUMULATION (Manual Sign Extension) ---
        // We manually repeat the sign bit [19] 12 times to extend 20->32 bits.
        final_sum <= 
            { {12{row_sums[0][19]}}, row_sums[0] } + 
            { {12{row_sums[1][19]}}, row_sums[1] } + 
            { {12{row_sums[2][19]}}, row_sums[2] } + 
            { {12{row_sums[3][19]}}, row_sums[3] } + 
            { {12{row_sums[4][19]}}, row_sums[4] };
    end

    assign result = final_sum;

endmodule