module layer2_rom_banked (
    input logic clk,
    input logic [3:0] bank_id, // Selects the channel (0-15)
    input logic [7:0] addr,
    output logic signed [7:0] weight_out
);
    logic signed [7:0] q [0:15];

    // Instantiate all 16 ROMs
    genvar i;
    generate
        for (i = 0; i < 16; i++) begin : banks
            layer2_weight_rom #(.CHANNEL_ID(i)) rom (
                .clk(clk),
                .addr(addr),
                .weight_out(q[i])
            );
        end
    endgenerate
    
    assign weight_out = q[bank_id];
endmodule