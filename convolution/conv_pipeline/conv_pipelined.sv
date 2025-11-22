module conv_pipelined (
    input logic clk,
    input logic signed [7:0] window [4:0][4:0],
    input logic signed [7:0] weights [4:0][4:0],
    output logic signed [31:0] result
);
    // Stage 1: Products (25 multipliers)
    logic signed [15:0] products [4:0][4:0];
    
    // Stage 2: Row Sums (5 adders)
    logic signed [20:0] row_sums [4:0];
    
    // Stage 3: Final Result (1 big adder)
    logic signed [31:0] final_sum;

    always_ff @(posedge clk) begin
        // --- PIPELINE STAGE 1: MULTIPLY ---
        // Latency = 1 cycle
        for(int i=0; i<5; i++) begin
            for(int j=0; j<5; j++) begin
                products[i][j] <= window[i][j] * weights[i][j];
            end
        end

        // --- PIPELINE STAGE 2: ADD ROWS ---
        // Latency = 2 cycles
        for(int i=0; i<5; i++) begin
            row_sums[i] <= products[i][0] + products[i][1] + 
                           products[i][2] + products[i][3] + products[i][4];
        end

        // --- PIPELINE STAGE 3: FINAL ACCUMULATION ---
        // Latency = 3 cycles
        final_sum <= row_sums[0] + row_sums[1] + row_sums[2] + row_sums[3] + row_sums[4];
    end

    // Output assignment
    assign result = final_sum;

endmodule