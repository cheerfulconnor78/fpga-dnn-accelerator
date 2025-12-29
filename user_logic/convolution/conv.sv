//5x5 convolution window
module conv (
    input logic clk, rst, start,
    input logic signed [7:0] weights [4:0][4:0],
    input logic signed [7:0] inputs[4:0][4:0],
    output logic signed [31:0] outputs,
    output logic done
);
    localparam SIZE = 5;
    logic signed [15:0] product;
    logic signed [31:0] accumulator;
    logic [4:0]count_reg;
    logic op_done;

    typedef enum { IDLE, RUN } state_t;
    state_t state;

    always_comb begin
        product = 16'b0;
        if(state == RUN) begin
            product = inputs[count_reg / 5][count_reg % 5] * weights[count_reg / 5][count_reg % 5];
        end
    end

    always_ff @(posedge clk) begin
        if(rst) begin
            state <= IDLE;
            accumulator <= 32'b0;   
            op_done <= 1'b0;
            count_reg <= 5'b0;

        end else begin
            op_done <= 1'b0;
            case (state)
                IDLE: begin
                    if(start) begin
                    state <= RUN;
                    accumulator <= 32'b0;
                    op_done <= 1'b0;
                    count_reg <= 5'b0;
                    end
                end
                RUN: begin
                    accumulator <= accumulator + product;
                    count_reg <= count_reg + 1;
                    if(count_reg == 24) begin
                        state <= IDLE;
                        op_done <= 1;
                    end
                end
            endcase
        end
    end

    assign outputs = accumulator;
    assign done = op_done;

endmodule

