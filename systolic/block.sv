//systolic matrix multiplier processing element
module block (
    input logic[7:0] in_north,
    input logic[7:0] in_west,
    input logic clk, rst
    output logic[7:0] out_south
    output logic[7:0] out_east
    output logic[31:0] result
);

logic [15:0] mult;
assign mult = in_north * in_west; 
always_ff @(posedge clk or posedge rst) begin
    if(rst) begin
        out_south <= 1'b0;
        out_east <= 1'b0;
        result <= 1'b0;
    end else begin
        out_east <= in_west;
        out_south <= in_north;
        result <= result + mult;
    end
end
    
endmodule