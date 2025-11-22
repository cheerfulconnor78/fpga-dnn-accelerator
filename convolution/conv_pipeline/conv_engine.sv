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
    // Size 4: 1 cycle (Buffer) + 3 cycles (Math Pipeline)
    logic [3:0] valid_pipe; 
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
    typedef enum { IDLE, STREAMING, FLUSH, DONE } state_t;
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
            
            // --- A. GLOBAL PIPELINE MANAGEMENT ---
            // This runs during STREAMING AND FLUSH.
            // It ensures the last few "valid" signals travel to the output
            // even after the input data stops.
            if (state == STREAMING || state == FLUSH) begin
                // Shift the pipe:
                // If Streaming + Valid Data: Shift in the condition.
                // If Flushing: Shift in '0' to clear the pipe.
                if (state == STREAMING && data_valid_in) 
                    valid_pipe[0] <= condition_met;
                else 
                    valid_pipe[0] <= 0;
                
                // Shift through 4 stages (Indices 0, 1, 2, 3)
                valid_pipe[1] <= valid_pipe[0];
                valid_pipe[2] <= valid_pipe[1];
                valid_pipe[3] <= valid_pipe[2];

                // Drive Output from the end of the pipe (Index 3)
                mem_wr_en <= valid_pipe[3];
                
                if (valid_pipe[3]) begin
                    mem_wr_data <= math_result; 
                    mem_wr_addr <= write_ctr;
                    write_ctr   <= write_ctr + 1;
                end
            end else begin
                mem_wr_en <= 0;
            end

            // --- B. STATE MACHINE ---
            case (state)
                IDLE: begin
                    all_done <= 0;
                    pixel_ctr <= 0;
                    col_ctr <= 0;
                    write_ctr <= 0;
                    valid_pipe <= 0;
                    if (start) state <= STREAMING;
                end

                STREAMING: begin
                    if (data_valid_in) begin
                        // Increment Counters
                        pixel_ctr <= pixel_ctr + 1;
                        
                        if (col_ctr == MAPSIZE - 1) 
                            col_ctr <= 0;
                        else 
                            col_ctr <= col_ctr + 1;

                        // Exit Condition:
                        // When we hit the last pixel, we are NOT done yet.
                        // We must go to FLUSH to let the pipeline drain.
                        if (pixel_ctr == TOTAL_PIXELS - 1) begin
                            state <= FLUSH;
                        end
                    end
                end
                
                FLUSH: begin
                    // Wait here until the pipeline empties out.
                    // When valid_pipe is all zeros, the last writes are finished.
                    if (valid_pipe == 0) begin
                        state <= DONE;
                    end
                end

                DONE: begin
                    all_done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule