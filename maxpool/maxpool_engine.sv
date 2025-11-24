module maxpool_engine #(
    parameter MAP_WIDTH = 28,
    parameter OUT_DIM = MAP_WIDTH / 2
) (
    input  logic clk,
    input  logic rst, 
    input  logic valid_in,
    input  logic signed [7:0] pixel_in,
    
    output logic valid_out,
    output logic signed [7:0] pixel_out,
    output logic all_done
);

    // 1. BUFFER INSTANTIATION
    logic signed [7:0] window [1:0][1:0];
    logic signed [7:0] line_out;
    
    maxpool_buffer #(.LENGTH(MAP_WIDTH)) u_buffer (
        .clk(clk), .rst(rst),
        .data_valid_in(valid_in),
        .line_out(line_out),
        .pixel_in(pixel_in),
        .window(window)
    );

    // 2. CANDIDATE CAPTURE (Combinational wires)
    logic signed [7:0] v0, v1, v2, v3;
    always_comb begin
        v0 = window[0][1]; // Top Left
        v1 = line_out;     // Top Right
        v2 = window[1][1]; // Bot Left
        v3 = pixel_in;     // Bot Right
    end

    // -------------------------------------------------------------
    // STRIDE CONTROL LOGIC
    // -------------------------------------------------------------
    logic [$clog2(MAP_WIDTH)-1:0] col_ptr;
    logic row_parity; 
    logic stride_trigger; // Internal wire

    // -------------------------------------------------------------
    // PIPELINE STAGE 1: FIRST LEVEL COMPARISONS
    // -------------------------------------------------------------
    // We compare Top pair and Bottom pair, and store the winners.
    logic signed [7:0] max_top_reg, max_bot_reg;
    logic valid_stage1; // Valid signal pipelined to follow data

    always_ff @(posedge clk) begin
        if (rst) begin
            max_top_reg <= 0;
            max_bot_reg <= 0;
            valid_stage1 <= 0;
        end else begin
            // Pass the "valid" signal down the pipe
            // Only fire if the stride logic (below) says so
            if (valid_in && stride_trigger) begin
                valid_stage1 <= 1;
                // Compare and Store
                max_top_reg <= (v0 > v1) ? v0 : v1;
                max_bot_reg <= (v2 > v3) ? v2 : v3;
            end else begin
                valid_stage1 <= 0;
            end
        end
    end

    // -------------------------------------------------------------
    // PIPELINE STAGE 2: FINAL COMPARISON
    // -------------------------------------------------------------
    // Compare the two winners from Stage 1
    always_ff @(posedge clk) begin
        if (rst) begin
            valid_out <= 0;
            pixel_out <= 0;
        end else begin
            valid_out <= valid_stage1;
            
            if (valid_stage1) begin
                pixel_out <= (max_top_reg > max_bot_reg) ? max_top_reg : max_bot_reg;
            end
        end
    end



    // Calculate stride condition (Combinational or Registered check)
    always_comb begin
        // We only trigger Stage 1 when this is true
        stride_trigger = (row_parity == 1'b1 && col_ptr[0] == 1'b1);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            col_ptr <= 0;
            row_parity <= 0;
        end else if (valid_in) begin
            if (col_ptr == MAP_WIDTH - 1) begin
                col_ptr <= 0;
                row_parity <= ~row_parity; 
            end else begin
                col_ptr <= col_ptr + 1;
            end
        end
    end

    // -------------------------------------------------------------
    // OUTPUT COUNTER (Uses valid_out which is now delayed by 1 cycle)
    // -------------------------------------------------------------
    localparam TOTAL_OUTPUTS = OUT_DIM * OUT_DIM;
    logic [$clog2(TOTAL_OUTPUTS):0] out_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            out_count <= 0;
            all_done <= 0;
        end else begin
            if (valid_out) begin
                if(out_count == TOTAL_OUTPUTS - 1) begin
                    all_done <= 1;
                    out_count <= 0;
                end else begin
                    out_count <= out_count + 1;
                end
            end
        end
    end

endmodule