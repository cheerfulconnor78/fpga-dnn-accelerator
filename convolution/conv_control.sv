//upper level control module that runs the 5x5 convolution engine over a feature map
module conv_control #(
    parameter MAPSIZE = 32
) (
    input logic clk, rst, start,
    input logic signed [7:0] feature [MAPSIZE-1:0][MAPSIZE-1:0],
    input logic signed [7:0] weights [4:0][4:0],
    output logic signed [31:0] outputs [MAPSIZE-5:0][MAPSIZE-5:0],
    output wire all_done
);  

    localparam LIMIT = MAPSIZE - 5;
    //# of bits required to encode the traversal in x and y directions
    localparam traversal_bits = $clog2(MAPSIZE-4);
    logic signed [7:0] window_in [4:0][4:0];
    logic signed [31:0] window_out;
    logic start_conv, conv_done;
    logic [traversal_bits-1:0] x_traversal;
    logic [traversal_bits-1:0] y_traversal;
    logic last_pixel_reached;
    assign last_pixel_reached = (y_traversal == LIMIT) && (x_traversal == LIMIT);
    assign all_done = (state == DONE);

    typedef enum { IDLE, PROCESSING, UPDATING, DONE } state_t;
    state_t state, nextstate;

    conv window (
        .clk(clk),
        .rst(rst),
        .start(start_conv),
        .weights(weights),
        .inputs(window_in),
        .outputs(window_out),
        .done(conv_done)
    );

    always_comb begin
        //default 
        nextstate = state;
        start_conv = 0;
        for (int r = 0; r < 5; r++) begin
            for (int c = 0; c < 5; c++) begin
                window_in[r][c] = 8'b0; 
            end
        end
        for(int i = 0; i < 5; i++) begin
            for(int j = 0; j < 5; j++) begin
                window_in[i][j] = feature[y_traversal + i][x_traversal + j];
            end
        end
        case (state)
            IDLE: begin
                //initialize window as the top left corner of the feed
                if(start) begin 
                    start_conv = 1;
                    nextstate = PROCESSING;
                end else begin
                    nextstate = IDLE;
                end
            end
            PROCESSING: begin
                if(conv_done) begin //done with 1 cycle
                    nextstate = UPDATING;
                end else begin
                    nextstate = PROCESSING;
                    start_conv = 1;
                end
            end
            UPDATING: begin //writing stage
                if(!last_pixel_reached) begin
                    nextstate = PROCESSING;
                end else begin
                    nextstate = DONE;   
                end
            end
            DONE: begin
                nextstate = DONE;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (state == IDLE) begin
            x_traversal <= 0;
            y_traversal <= 0;
        end
        if(rst) begin
            state <= IDLE;
            x_traversal <= '0;
            y_traversal <= '0;
        end else begin
            state <= nextstate;
            if(state == UPDATING) begin
                if(x_traversal == LIMIT) begin
                    if(y_traversal != LIMIT) begin
                        x_traversal <= 0;
                        y_traversal <= y_traversal + 1;
                    end
                end else begin
                    x_traversal <= x_traversal + 1;
                end    
            end
            if(state == PROCESSING && conv_done) begin
                outputs[y_traversal][x_traversal] <= window_out;
            end
        end
    end
endmodule
