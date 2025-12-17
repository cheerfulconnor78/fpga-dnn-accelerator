module layer1_weight_rom #(
    parameter CHANNEL_ID = 0
)(
    input logic clk,
    input logic [4:0] addr, // 0 to 24 (for 5x5 weights)
    output logic signed [7:0] weight_out
);

    // This forces Quartus to use M10K blocks or LUTRAM automatically
    (* ramstyle = "logic" *) // or "M10K" if you prefer
    logic signed [7:0] mem [0:24];

    // Initialize with different files based on ID
    // Note: You must generate these .mif files (w_c1_0.mif, w_c1_1.mif, etc.)
    generate
        case(CHANNEL_ID)
            0: initial $readmemh("top/weights_generator/c1_weights/weights_c1_0.hex", mem);
            1: initial $readmemh("top/weights_generator/c1_weights/weights_c1_1.hex", mem);
            2: initial $readmemh("top/weights_generator/c1_weights/weights_c1_2.hex", mem);
            3: initial $readmemh("top/weights_generator/c1_weights/weights_c1_3.hex", mem);
            4: initial $readmemh("top/weights_generator/c1_weights/weights_c1_4.hex", mem);
            5: initial $readmemh("top/weights_generator/c1_weights/weights_c1_5.hex", mem);
        endcase
    endgenerate

    always_ff @(posedge clk) begin
        weight_out <= mem[addr];
    end

endmodule