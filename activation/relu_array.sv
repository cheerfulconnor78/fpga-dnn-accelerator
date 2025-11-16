module relu_array (
    input logic[31:0] weights_in[7:0][7:0],
    output logic[31:0] weights_out[7:0][7:0]
);
    localparam SIZE = 8;
    genvar i,j;
    generate
        for(i = 0; i < SIZE; i++) begin
            for(j = 0; j < SIZE; j++) begin
                relu(
                    .weight_in(weights_in[i][j]),
                    .weight_out(weights_out[i][j])
                )
            end
        end 
    endgenerate
endmodule