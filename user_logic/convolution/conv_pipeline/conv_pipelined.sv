module conv_pipelined (
    input logic clk,
    // No reset needed for pure datapath (flush handling is done by control logic)
    input logic signed [7:0] window [4:0][4:0],
    input logic signed [7:0] weights [4:0][4:0],
    output logic signed [31:0] result
);
    // --- STAGE 1: MULTIPLICATION ---
    // Latency: 1 Cycle
    logic signed [15:0] products [4:0][4:0];

    always_ff @(posedge clk) begin
        for(int i=0; i<5; i++) begin
            for(int j=0; j<5; j++) begin
                products[i][j] <= window[i][j] * weights[i][j];
            end
        end
    end

    // --- STAGE 2: ROW SUMS (PART A) ---
    // Break the 5-input add into smaller 2-input adds.
    // Add (0+1) and (2+3). buffer (4).
    // Latency: 2 Cycles (accumulated)
    logic signed [19:0] row_part1 [4:0];
    logic signed [19:0] row_part2 [4:0];
    logic signed [19:0] row_part3 [4:0];

    always_ff @(posedge clk) begin
        for(int i=0; i<5; i++) begin
            // Note: SystemVerilog handles sign extension automatically 
            // when adding smaller signed vars into larger signed vars.
            row_part1[i] <= products[i][0] + products[i][1];
            row_part2[i] <= products[i][2] + products[i][3];
            row_part3[i] <= products[i][4];
        end
    end

    // --- STAGE 3: ROW SUMS (PART B) ---
    // Finish the row sums: (Part1 + Part2 + Part3)
    // Latency: 3 Cycles (accumulated)
    logic signed [19:0] row_sums [4:0];

    always_ff @(posedge clk) begin
        for(int i=0; i<5; i++) begin
            row_sums[i] <= row_part1[i] + row_part2[i] + row_part3[i];
        end
    end

    // --- STAGE 4: FINAL ACCUMULATION (PART A) ---
    // Sum the 5 rows. Again, split into pairs.
    // Latency: 4 Cycles (accumulated)
    logic signed [31:0] col_part1; // Row 0 + 1
    logic signed [31:0] col_part2; // Row 2 + 3
    logic signed [31:0] col_part3; // Row 4

    always_ff @(posedge clk) begin
        col_part1 <= row_sums[0] + row_sums[1];
        col_part2 <= row_sums[2] + row_sums[3];
        col_part3 <= row_sums[4];
    end

    // --- STAGE 5: FINAL ACCUMULATION (PART B) ---
    // Finish the total sum.
    // Latency: 5 Cycles (accumulated)
    logic signed [31:0] final_sum;

    always_ff @(posedge clk) begin
        final_sum <= col_part1 + col_part2 + col_part3;
    end

    assign result = final_sum;

endmodule