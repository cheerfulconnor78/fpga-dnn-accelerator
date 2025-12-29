module maxpool_buffer #(
    parameter LENGTH = 28
) (
    input logic clk, rst, data_valid_in,
    input logic signed [7:0] pixel_in,
    output logic signed [7:0] line_out,
    output logic signed [7:0] window [1:0][1:0]
);

    // Internal Line Buffers using the Parameter
    logic signed [7:0] row_buf [LENGTH-1:0];

    // Vertical Taps
    logic signed [7:0] taps [1:0];

    assign taps[0] = pixel_in;
    assign taps[1] = row_buf[LENGTH-1];

    assign line_out = row_buf[LENGTH -1];

    always_ff @(posedge clk) begin
        if (rst) begin
            // Reset Buffers
            for (int i=0; i<LENGTH; i++) begin
                row_buf[i] <= 8'h80;
            end
            // Reset Window
            for (int r=0; r<2; r++)
                for (int c=0; c<2; c++)
                    window[r][c] <= 8'h80;
        end 
        else if (data_valid_in) begin
            // Shift Line Buffers, stride = 2
            for (int i=LENGTH-1; i>0; i = i - 1) begin
                row_buf[i] <= row_buf[i-1];
            end
            
            // Feed Data into Starts
            row_buf[0] <= pixel_in;

            // Shift Window Registers
            for (int r=0; r<2; r++) begin
                window[r][0] <= window[r][1];
                window[r][1] <= taps[1-r]; 
            end
        end
    end
endmodule