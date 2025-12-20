module output_max (
    input clk, rst,
    input signed [7:0] data_in,
    input data_valid_in,
    input layer_done_in,
    output [3:0] prediction, //final prediction
    output prediction_valid
);
    logic signed [7:0] max_val;
    logic [3:0] max_idx;
    logic [3:0] current_idx;

    always_ff @(posedge clk) begin
        if(rst) begin
            max_val <= -128; // Initialize to min signed value
            max_idx <= 0;
            current_idx <= 0;
            prediction <= 0;
            prediction_valid <= 0;
        end else begin
            prediction_valid <= 0;

            // ONLY update when valid data arrives
            if (data_valid_in) begin
                if (data_in > max_val) begin
                    max_val <= data_in;
                    max_idx <= current_idx;
                end

                if(current_idx == 9) begin
                    current_idx <= 0;
                end else begin
                    current_idx <= current_idx + 1;
                end
            end

            if(layer_done_in) begin
                prediction <= max_idx;
                prediction_valid <= 1;

                // Reset for next frame
                max_val <= -128; 
                max_idx <= 0;
                current_idx <= 0;
            end
        end
    end
endmodule