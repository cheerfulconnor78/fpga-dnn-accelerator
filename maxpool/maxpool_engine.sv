//computes full maxpool layer
module pool_layer_parallel #(
    parameter IN_SIZE = 24,
    parameter OUT_SIZE = 12 // IN_SIZE / 2
) (
    input logic signed [7:0] feature_map [IN_SIZE-1:0][IN_SIZE-1:0],
    output logic signed [7:0] pooled_map [OUT_SIZE-1:0][OUT_SIZE-1:0]
);

    genvar y, x;

    generate
        for (y = 0; y < OUT_SIZE; y++) begin : ROW
            for (x = 0; x < OUT_SIZE; x++) begin : COL
                maxpool u_pool (
                    .grid( '{ '{feature_map[y*2][x*2],   feature_map[y*2][x*2+1]}, 
                              '{feature_map[y*2+1][x*2], feature_map[y*2+1][x*2+1]} } ),
                    .out ( pooled_map[y][x] )
                );
            end
        end
    endgenerate
endmodule