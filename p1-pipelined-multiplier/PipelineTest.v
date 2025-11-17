module OneHotCalculator(
    input Start,
    input Clear,
    input CLK_50,
    output reg [7:0] LED_OUT
);

    reg X, X_Next;
    localparam XIdle = 1'b0, XStart = 1'b1;
    reg[3:0] cycle_counter;


    reg[3:0] mcand_reg;
    reg[3:0] mplier_reg;


    reg [3:0] mcand_p1, mplier_p1; // First pipeline stage
    reg [7:0] product_p2;         // Second pipeline stage (result)

    always @(posedge CLK_50) begin
        // Pipeline Stage 1: Register the inputs
        mcand_p1 <= mcand_reg;
        mplier_p1 <= mplier_reg;

        // Pipeline Stage 2: Perform multiplication on registered inputs
        product_p2 <= mcand_p1 * mplier_p1;
    end


    // Control logic 
    always @(posedge CLK_50) begin
        if(Clear) X <= XIdle;
        else X <= X_Next;
    end

    always @* begin
        X_Next = X;
        case (X)
            XIdle: begin
                if(Start) begin
                    X_Next = XStart;
                end else begin 
                    X_Next = XIdle;
                end
            end
            XStart: begin
                if(cycle_counter == 4'd8) begin
                    X_Next = XIdle;
                end
            end
        endcase
    end

    // Datapath logic (no changes)
    always @(posedge CLK_50) begin
        if(Clear || X == XIdle) begin
            mcand_reg <= 4'd0;
            mplier_reg <= 4'd1;
            cycle_counter <= 4'd0;
        end else if (X == XStart) begin 
            mcand_reg <= mcand_reg + 1;
            mplier_reg <= mplier_reg + 1;
            cycle_counter <= cycle_counter + 1;
        end
        // Assign the final pipelined result to the output
        LED_OUT <= product_p2;
    end
endmodule