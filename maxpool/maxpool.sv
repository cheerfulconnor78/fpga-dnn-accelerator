//2x2 maxpool module
module maxpool (
    input logic signed [7:0] grid [1:0][1:0],
    output logic signed [7:0] out
);
    logic signed [7:0] comp1, comp2;
    assign comp1 = (grid[0][0] > grid [0][1]) ? grid[0][0] : grid[0][1];
    assign comp2 = (grid[1][0] > grid [1][1]) ? grid[1][0] : grid[1][1];
    assign out = (comp1 > comp2) ? comp1 : comp2;
endmodule