module row_buffer #(
    parameter LENGTH = 32
) (
    input logic clk, rst, data_valid_in,
    input logic signed [7:0] pixel_in,
    output logic signed [7:0] window [4:0][4:0]
);

    // Internal Line Buffers using the Parameter
    logic signed [7:0] row_buf_0 [LENGTH-1:0];
    logic signed [7:0] row_buf_1 [LENGTH-1:0];
    logic signed [7:0] row_buf_2 [LENGTH-1:0];
    logic signed [7:0] row_buf_3 [LENGTH-1:0];
    
    // Vertical Taps
    logic signed [7:0] taps [4:0];

    assign taps[0] = pixel_in;
    assign taps[1] = row_buf_0[LENGTH-1];
    assign taps[2] = row_buf_1[LENGTH-1];
    assign taps[3] = row_buf_2[LENGTH-1];
    assign taps[4] = row_buf_3[LENGTH-1];
    
    always_ff @(posedge clk) begin
        if (rst) begin
            // Reset Buffers
            for (int i=0; i<LENGTH; i++) begin
                row_buf_0[i] <= 8'b0; row_buf_1[i] <= 8'b0;
                row_buf_2[i] <= 8'b0; row_buf_3[i] <= 8'b0;
            end
            // Reset Window
            for (int r=0; r<5; r++)
                for (int c=0; c<5; c++)
                    window[r][c] <= 8'b0;
        end 
        else if (data_valid_in) begin
            // Shift Line Buffers
            for (int i=LENGTH-1; i>0; i--) begin
                row_buf_0[i] <= row_buf_0[i-1];
                row_buf_1[i] <= row_buf_1[i-1];
                row_buf_2[i] <= row_buf_2[i-1];
                row_buf_3[i] <= row_buf_3[i-1];
            end
            
            // Feed Data into Starts
            row_buf_0[0] <= pixel_in;
            row_buf_1[0] <= row_buf_0[LENGTH-1];
            row_buf_2[0] <= row_buf_1[LENGTH-1];
            row_buf_3[0] <= row_buf_2[LENGTH-1];

            // Shift Window Registers
            for (int r=0; r<5; r++) begin
                window[r][0] <= window[r][1];
                window[r][1] <= window[r][2];
                window[r][2] <= window[r][3];
                window[r][3] <= window[r][4];
                window[r][4] <= taps[r]; 
            end
        end
    end
endmodule