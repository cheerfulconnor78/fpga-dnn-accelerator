module maxpool_engine #(
    parameter MAP_WIDTH = 28
    parameter OUT_DIM = MAP_WIDTH / 2;
) (
    input  logic clk,
    input  logic rst, 
    input  logic valid_in,
    input  logic signed [7:0] pixel_in,
    
    output logic valid_out,
    output logic signed [7:0] pixel_out,
    output logic all_done
);

    logic signed [7:0] window [1:0][1:0];
    
    maxpool_buffer #(.LENGTH(MAP_WIDTH)) u_buffer (
        .clk(clk), .rst(rst),
        .data_valid_in(valid_in),
        .pixel_in(pixel_in),
        .window(window)
    );

    // Counters for Stride Control
    logic [$clog2(MAP_WIDTH)-1:0] col_ptr;
    logic row_parity; // 0 = Even, 1 = Odd

    logic signed [7:0] max_top, max_bot, max_val;
    
    always_comb begin
        max_top = (window[0][0] > window[0][1]) ? window[0][0] : window[0][1];
        max_bot = (window[1][0] > window[1][1]) ? window[1][0] : window[1][1];
        max_val = (max_top > max_bot)           ? max_top     : max_bot;
    end

    logic total_outputs = OUT_DIM * OUT_DIM;
    logic out_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            col_ptr <= 0;
            row_parity <= 0;
            valid_out <= 0;
            pixel_out <= 0;
        end else if (valid_in) begin
            // Update Counters
            if (col_ptr == MAP_WIDTH - 1) begin
                col_ptr <= 0;
                row_parity <= ~row_parity; // toggle row parity
            end else begin
                col_ptr <= col_ptr + 1;
            end

            // Stride Check (Stride = 2)
            // We want the window when we have collected pixels [0,1] on rows [0,1]
            // This happens when col_ptr is 1 (the second pixel) and row_parity is 1 (the second row)
            if (row_parity == 1'b1 && col_ptr[0] == 1'b1) begin
                valid_out <= 1'b1;
                pixel_out <= max_val;
            end else begin
                valid_out <= 1'b0;
            end
        end else begin
            valid_out <= 1'b0;
        end

        if (valid_out) begin
            if(out_count == total_outputs - 1) begin
                all_done <= 1;
                out_count <= 0;
            end else begin
                out_count <= out_count + 1;
            end
        end
    end
endmodule