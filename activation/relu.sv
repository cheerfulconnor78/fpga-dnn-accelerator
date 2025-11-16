module relu (
    input logic[31:0] weight_in,
    output logic[31:0] weight_out
);
    assign weight_out = weight_in[31] ? 0 : weight_in;
endmodule