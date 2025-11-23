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

    logic signed [7:0] window [1:0][1:0];
    logic signed [7:0] line_out;
    
    maxpool_buffer #(.LENGTH(MAP_WIDTH)) u_buffer (
        .clk(clk), .rst(rst),
        .data_valid_in(valid_in),
        .line_out(line_out),
        .pixel_in(pixel_in),
        .window(window)
    );

    logic [$clog2(MAP_WIDTH)-1:0] col_ptr;
    logic row_parity; 

    // --- ROBUST COMPARATOR WIRES ---
    logic signed [7:0] v0, v1, v2, v3;
    logic signed [7:0] max_top, max_bot, max_final;

    always_comb begin
        // 1. Capture the 4 candidates
        v0 = window[0][1]; // Top Left
        v1 = line_out;     // Top Right
        v2 = window[1][1]; // Bot Left
        v3 = pixel_in;     // Bot Right

        // 2. Compare using robust signed wires
        max_top   = (v0 > v1) ? v0 : v1;
        max_bot   = (v2 > v3) ? v2 : v3;
        max_final = (max_top > max_bot) ? max_top : max_bot;
    end

    localparam TOTAL_OUTPUTS = OUT_DIM * OUT_DIM;
    logic [$clog2(TOTAL_OUTPUTS):0] out_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            col_ptr <= 0;
            row_parity <= 0;
            valid_out <= 0;
            pixel_out <= 0;
            out_count <= 0;
            all_done <= 0;
        end else begin
            
            if (valid_in) begin
                if (col_ptr == MAP_WIDTH - 1) begin
                    col_ptr <= 0;
                    row_parity <= ~row_parity; 
                end else begin
                    col_ptr <= col_ptr + 1;
                end

                if (row_parity == 1'b1 && col_ptr[0] == 1'b1) begin
                    valid_out <= 1'b1;
                    pixel_out <= max_final;
                    
                    // --- DEBUG PRINT ---
                    // This will show us EXACTLY why the hardware picked the wrong number
                    $display("DEBUG: Out#%0d | Cand: %0d %0d %0d %0d | Picked: %0d", 
                             out_count, v0, v1, v2, v3, max_final);

                end else begin
                    valid_out <= 1'b0;
                end
            end else begin
                valid_out <= 1'b0;
            end

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