module lenet_top_parallel (
    input logic clk, rst, start,

    // Single Input Stream (Broadcast to all)
    input logic data_valid_in,
    input logic signed [7:0] pixel_in,

    // 6 Parallel Output Streams
    output logic [5:0] data_valid_out,
    output logic [5:0][7:0] pixel_out,
    output logic [5:0] layer_done
);

    // Use a generate loop to create 6 hardware instances
    genvar i;
    generate
        for (i = 0; i < 6; i++) begin : channels
            lenet_channel #(
                .CHANNEL_ID(i)
            ) u_core (
                .clk(clk),
                .rst(rst),
                .start(start),
                .data_valid_in(data_valid_in),
                .pixel_in(pixel_in),
                
                // Outputs are sliced into the array
                .data_valid_out(data_valid_out[i]),
                .pixel_out(pixel_out[i]),
                .layer_done(layer_done[i])
            );
        end
    endgenerate

endmodule