module systolic #(parameter ARRSIZE = 8)(
    input clk, rst,
    input [7:0] row_weights[7:0], //A inputs
    input [7:0] col_activations[7:0], //X inputs
    output [31:0] result [7:0][7:0] //Y = AX
);

logic[7:0] a_wire[7:0][8:0]; //connecting horizontal datapath
logic[7:0] x_wire[8:0][7:0]; //connecting vertical datapath
//logic [31:0] res[7:0][7:0]; //result matrix

genvar i, j;
generate
    for(i = 0; i < ARRSIZE; i++) begin
        assign a_wire[i][0] = row_weights[i];
        assign x_wire[0][i] = col_activations[i];
    end
endgenerate
generate
    for(i = 0; i < ARRSIZE; i++) begin
        for (j = 0; j < ARRSIZE; j++) begin
            block pe_inst (
                .in_north(x_wire[i][j]),
                .in_west(a_wire[i][j]),
                .out_south(x_wire[i+1][j]),
                .out_east(a_wire[i][j+1]),
                .rst(rst),
                .clk(clk),
                .result(result[i][j]));
        end 
    end
endgenerate    
endmodule

