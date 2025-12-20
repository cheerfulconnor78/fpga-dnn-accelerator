module fc_streaming #(
    parameter NUM_INPUTS = 400,
    parameter NUM_OUTPUTS = 120,
    parameter WEIGHT_FILE = "top/weights_generator/fc_weights/c5_weights_flattened.hex",
    parameter ENABLE_RELU = 1,
    parameter SHIFT = 10
) (
    input logic clk, rst,
    input logic signed [7:0] data_in,
    input logic data_valid_in,
    
    output logic signed [7:0] data_out,
    output logic data_valid_out,
    output logic done
);
    // 1. INPUT RING BUFFER (Inferred M10K)
    (* ramstyle = "M10K" *)
    logic signed [7:0] input_ram [0:NUM_INPUTS-1];
    logic [$clog2(NUM_INPUTS)-1:0] wr_ptr;

    // 2. WEIGHT ROM (Now External)
    // We calculate the address here, but the memory is in the instance below
    logic [15:0] weight_addr;
    logic signed [7:0] weight_wire; // Output from ROM instance

    fc_weight_rom #(
        .NUM_WORDS(NUM_INPUTS * NUM_OUTPUTS),
        .WEIGHT_FILE(WEIGHT_FILE)
    ) rom_inst (
        .clk(clk),
        .addr(weight_addr[ $clog2(NUM_INPUTS*NUM_OUTPUTS)-1 : 0 ]), // Cast to correct width
        .q(weight_wire)
    );

    // Pointers
    logic [$clog2(NUM_INPUTS)-1:0] rd_ptr;

    // 3. PIPELINE REGISTERS
    logic signed [7:0] pixel_reg;
    // logic signed [7:0] weight_reg; // REMOVED: Replaced by weight_wire
    logic pipeline_valid;

    // 4. ACCUMULATION & COUNTERS
    logic signed [31:0] accumulator;
    logic layer_done_reg;
    logic [$clog2(NUM_INPUTS):0] acc_counter;
    logic signed [31:0] scaled_acc_wire;
    assign scaled_acc_wire = accumulator >>> SHIFT;
    logic [$clog2(NUM_OUTPUTS):0] output_count;

    assign done = layer_done_reg;

    typedef enum {IDLE, LOAD, COMPUTING, DONE} state_t;
    state_t state;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            wr_ptr <= 0;
            rd_ptr <= 0;
            weight_addr <= 0;
            
            accumulator <= 0;
            pixel_reg <= 0;
            // weight_reg <= 0; // REMOVED
            pipeline_valid <= 0;
            
            acc_counter <= 0;
            output_count <= 0;
            
            data_valid_out <= 0;
            data_out <= 0;
            layer_done_reg <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (data_valid_in) begin
                        // CAPTURE THE FIRST PIXEL!
                        input_ram[wr_ptr] <= data_in;
                        wr_ptr <= wr_ptr + 1;
                        state <= LOAD;
                    end
                end

                // PHASE 1: FILL RING BUFFER
                LOAD: begin
                    if (data_valid_in) begin
                        input_ram[wr_ptr] <= data_in;
                        if (wr_ptr == NUM_INPUTS - 1) begin
                            state <= COMPUTING;
                            wr_ptr <= 0; 
                            rd_ptr <= 0;
                            weight_addr <= 0;
                            acc_counter <= 0;
                            output_count <= 0;
                            pipeline_valid <= 0;
                            accumulator <= 0;
                        end else begin
                            wr_ptr <= wr_ptr + 1;
                        end
                    end
                end

                // PHASE 2: STREAMING COMPUTE
                COMPUTING: begin
                    data_valid_out <= 0;
                    
                    // --- STEP A: FETCH DATA ---
                    pixel_reg  <= input_ram[rd_ptr];
                    // weight_reg <= weight_rom[weight_addr]; // REMOVED
                    // The 'rom_inst' automatically fetches 'weight_wire' based on 'weight_addr'
                    
                    // Increment Pointers
                    if (rd_ptr == NUM_INPUTS - 1) rd_ptr <= 0;
                    else rd_ptr <= rd_ptr + 1;

                    if (weight_addr != (NUM_INPUTS * NUM_OUTPUTS)) 
                        weight_addr <= weight_addr + 1;

                    // --- STEP B: EXECUTE MATH ---
                    pipeline_valid <= 1;
                    if (pipeline_valid) begin
                        // Use 'weight_wire' directly. It arrives at the same time pixel_reg does.
                        accumulator <= accumulator + (pixel_reg * weight_wire);
                        
                        if (acc_counter == NUM_INPUTS - 1) begin
                            acc_counter <= 0;       
                            // ---------------------------------------------------------
                            // SATURATION LOGIC (Uses the external wire)
                            // ---------------------------------------------------------
                            if (ENABLE_RELU) begin
                                // ReLU: [0 to 127]
                                if (scaled_acc_wire < 0) 
                                    data_out <= 8'd0;
                                else if (scaled_acc_wire > 127) 
                                    data_out <= 8'd127;
                                else 
                                    data_out <= scaled_acc_wire[7:0];
                            end else begin
                                // Output Layer: [-128 to 127]
                                if (scaled_acc_wire > 127) 
                                    data_out <= 8'd127;
                                else if (scaled_acc_wire < -128) 
                                    data_out <= -8'd128; 
                                else 
                                    data_out <= scaled_acc_wire[7:0];
                            end
                            
                            data_valid_out <= 1;
                            accumulator <= 0;

                            if (output_count == NUM_OUTPUTS - 1) begin
                                state <= DONE;
                            end else begin
                                output_count <= output_count + 1;
                            end

                        end else begin
                            acc_counter <= acc_counter + 1;
                        end
                    end
                end

                DONE: begin
                    data_valid_out <= 0;
                    layer_done_reg <= 1;
                    state <= IDLE;
                    wr_ptr <= 0;
                    rd_ptr <= 0;
                end
            endcase
        end
    end
endmodule