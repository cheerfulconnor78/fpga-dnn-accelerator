module conv_pipelined (
    input logic clk,
    input logic signed [7:0] window [4:0][4:0],
    input logic signed [7:0] weights [4:0][4:0],
    output logic signed [31:0] result
);
    // Stage 1: Products (16 bits is safe for 8x8 mult)
    logic signed [15:0] products [4:0][4:0];
    
    // Stage 2: Row Sums
    // Using 20 bits to comfortably hold the sum of 5 16-bit numbers
    logic signed [19:0] row_sums [4:0];
    
    // Stage 3: Final Result
    logic signed [31:0] final_sum;

    always_ff @(posedge clk) begin
        // --- STAGE 1: MULTIPLY ---
        for(int i=0; i<5; i++) begin
            for(int j=0; j<5; j++) begin
                // Multiply 8-bit inputs to get 16-bit product
                products[i][j] <= window[i][j] * weights[i][j];
            end
        end

        // --- STAGE 2: ADD ROWS ---
        for(int i=0; i<5; i++) begin
            // Force sign extension of the 16-bit products to the destination width (20 bits)
            // This prevents the "zero padding vs sign extension" bug.
            row_sums[i] <= 
                20'(products[i][0]) + 
                20'(products[i][1]) + 
                20'(products[i][2]) + 
                20'(products[i][3]) + 
                20'(products[i][4]);
        end

        // --- STAGE 3: FINAL ACCUMULATION ---
        // Force sign extension of the 20-bit sums to the final 32-bit width
        final_sum <= 
            32'(row_sums[0]) + 
            32'(row_sums[1]) + 
            32'(row_sums[2]) + 
            32'(row_sums[3]) + 
            32'(row_sums[4]);
    end

    assign result = final_sum;

endmodule