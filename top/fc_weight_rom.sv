module fc_weight_rom #(
    parameter NUM_WORDS = 48000,
    parameter WEIGHT_FILE = "c5_weights_flattened.hex"
)(
    input logic clk,
    input logic [$clog2(NUM_WORDS)-1:0] addr,
    output logic signed [7:0] q
);

    // Force M10K Block RAM
    (* ramstyle = "logic" *)
    logic signed [7:0] mem [0:NUM_WORDS-1];

    // Initialize from file
    initial begin
        $readmemh(WEIGHT_FILE, mem);
    end

    // Synchronous Read
    always_ff @(posedge clk) begin
        q <= mem[addr];
    end

endmodule