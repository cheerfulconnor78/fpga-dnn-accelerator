module conv_engine #(
    parameter MAPSIZE = 32
) (
    input logic clk, rst, start,
    
    // STREAMING INTERFACE
    input logic data_valid_in,          
    input logic signed [7:0] pixel_in,  
    
    // CONSTANT WEIGHTS
    input logic signed [7:0] weights [4:0][4:0],
    
    // BRAM WRITE INTERFACE
    output logic [$clog2((MAPSIZE-4)*(MAPSIZE-4))-1:0] mem_wr_addr,
    output logic signed [31:0] mem_wr_data,
    output logic mem_wr_en,
    
    output logic all_done
);

    localparam TOTAL_PIXELS  = MAPSIZE * MAPSIZE;
    localparam OUTPUT_COUNT  = (MAPSIZE - 4) * (MAPSIZE - 4);
    localparam PRIMING_STEPS = (MAPSIZE * 4) + 4; 

    // Bit widths
    localparam PIXEL_CTR_W   = $clog2(TOTAL_PIXELS);
    localparam COL_CTR_W     = $clog2(MAPSIZE);
    localparam OUT_ADDR_W    = $clog2(OUTPUT_COUNT);

    // Internal signals
    logic signed [7:0] current_window [4:0][4:0];
    logic signed [31:0] math_result;
    
    logic [PIXEL_CTR_W-1:0] pixel_ctr; 
    logic [COL_CTR_W-1:0]   col_ctr;   
    logic [OUT_ADDR_W-1:0]  write_ctr; 

    // Delay pipeline for alignment
    logic [1:0] valid_pipe; 
    logic condition_met;

    // 1. Instantiate Buffer
    row_buffer #(
        .LENGTH(MAPSIZE)
    ) window_gen (
        .clk(clk),
        .rst(rst),
        .data_valid_in(data_valid_in),
        .pixel_in(pixel_in),
        .window(current_window)
    );

    // 2. Instantiate Math Core
    conv_pipelined math_unit (
        .clk(clk),
        .window(current_window),
        .weights(weights),
        .result(math_result)
    );

    // 3. Control Logic
    typedef enum { IDLE, STREAMING, DONE } state_t;
    state_t state;

    // "Fast" condition check based on input counters
    assign condition_met = (pixel_ctr >= PRIMING_STEPS && col_ctr >= 4);

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            pixel_ctr <= 0;
            col_ctr <= 0;
            write_ctr <= 0;
            mem_wr_en <= 0;
            all_done <= 0;
            valid_pipe <= 0;
        end else begin
            case (state)
                IDLE: begin
                    all_done <= 0;
                    pixel_ctr <= 0;
                    col_ctr <= 0;
                    write_ctr <= 0;
                    valid_pipe <= 0;
                    mem_wr_en <= 0;
                    if (start) state <= STREAMING;
                end

                STREAMING: begin
                    if (data_valid_in) begin
                        // --- A. INPUT COUNTERS ---
                        // Track where we are in the input stream
                        pixel_ctr <= pixel_ctr + 1;
                        
                        if (col_ctr == MAPSIZE - 1) 
                            col_ctr <= 0;
                        else 
                            col_ctr <= col_ctr + 1;

                        // --- B. PIPELINE MANAGEMENT (The Fix) ---
                        // Shift the valid signal to match the latency of row_buffer + math_unit
                        valid_pipe[0] <= condition_met;
                        valid_pipe[1] <= valid_pipe[0];

                        // --- C. OUTPUT GENERATION ---
                        // Use the delayed signal to drive the write
                        mem_wr_en <= valid_pipe[1];
                        
                        if (valid_pipe[1]) begin
                            mem_wr_data <= math_result; 
                            mem_wr_addr <= write_ctr;
                            write_ctr   <= write_ctr + 1;
                        end

                        // --- D. EXIT CONDITION ---
                        if (pixel_ctr == TOTAL_PIXELS - 1) begin
                            state <= DONE;
                            mem_wr_en <= 0; 
                        end
                    end else begin
                        // Pause writing if input pauses
                        mem_wr_en <= 0; 
                    end
                end

                DONE: begin
                    all_done <= 1;
                    mem_wr_en <= 0;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule