module layer2_weight_rom #(
    parameter CHANNEL_ID = 0
)(
    input logic clk,
    input logic [7:0] addr, // 0 - 149
    output logic signed [7:0] weight_out
);

    // This forces Quartus to use M10K blocks or LUTRAM automatically
    (* ramstyle = "logic" *) // or "M10K" if you prefer
    logic signed [7:0] mem [0:149]; //6 * 5 * 5

    // Initialize with different files based on ID
    // Note: You must generate these .mif files (w_c1_0.mif, w_c1_1.mif, etc.)
    generate
        case(CHANNEL_ID)
            0: initial $readmemh("top/weights_generator/c2_weights/weights_c2_0.hex", mem);
            1: initial $readmemh("top/weights_generator/c2_weights/weights_c2_1.hex", mem);
            2: initial $readmemh("top/weights_generator/c2_weights/weights_c2_2.hex", mem);
            3: initial $readmemh("top/weights_generator/c2_weights/weights_c2_3.hex", mem);
            4: initial $readmemh("top/weights_generator/c2_weights/weights_c2_4.hex", mem);
            5: initial $readmemh("top/weights_generator/c2_weights/weights_c2_5.hex", mem);
            6: initial $readmemh("top/weights_generator/c2_weights/weights_c2_6.hex", mem);
            7: initial $readmemh("top/weights_generator/c2_weights/weights_c2_7.hex", mem);
            8: initial $readmemh("top/weights_generator/c2_weights/weights_c2_8.hex", mem);
            9: initial $readmemh("top/weights_generator/c2_weights/weights_c2_9.hex", mem);
            10: initial $readmemh("top/weights_generator/c2_weights/weights_c2_10.hex", mem);
            11: initial $readmemh("top/weights_generator/c2_weights/weights_c2_11.hex", mem);
            12: initial $readmemh("top/weights_generator/c2_weights/weights_c2_12.hex", mem);
            13: initial $readmemh("top/weights_generator/c2_weights/weights_c2_13.hex", mem);
            14: initial $readmemh("top/weights_generator/c2_weights/weights_c2_14.hex", mem);
            15: initial $readmemh("top/weights_generator/c2_weights/weights_c2_15.hex", mem);
        endcase
    endgenerate

    always_ff @(posedge clk) begin
        weight_out <= mem[addr];
    end

endmodule