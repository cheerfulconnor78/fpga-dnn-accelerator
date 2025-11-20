module conv_pipelined (
    input logic clk,
    input logic signed [7:0] window [4:0][4:0],
    input logic signed [7:0] weights [4:0][4:0],
    output logic signed [31:0] result
);
    logic signed [31:0] sum;

    always_ff @(posedge clk) begin
        sum = 0;
        for(int i=0; i<5; i++) begin
            for(int j=0; j<5; j++) begin
                sum += window[i][j] * weights[i][j];
            end
        end
        result <= sum;
    end
endmodule