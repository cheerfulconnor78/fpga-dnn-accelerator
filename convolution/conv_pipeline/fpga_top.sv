module fpga_top (
    input  logic clk,       //50MHz Clock
    input  logic rst_n,     //Key 0 (Active Low)
    output logic [1:0] led  //LED 0 = Done, LED 1 = Error
);

    localparam MAPSIZE = 32;
    localparam TOTAL_PIXELS = MAPSIZE * MAPSIZE;
    localparam OUTPUT_COUNT = (MAPSIZE-4) * (MAPSIZE-4);

    logic rst;
    assign rst = ~rst_n; //invert active-low button

    //rom instantiation
    logic signed [7:0]  image_rom  [0:TOTAL_PIXELS-1];
    logic signed [31:0] golden_rom [0:OUTPUT_COUNT-1];

    initial begin
        $readmemh("image.mem", image_rom);
        $readmemh("golden.mem", golden_rom);
    end

    //hardcoded test weights
    logic signed [7:0] weights [4:0][4:0];
    initial begin
        weights = '{
            '{ 0,  0, -1,  0,  0},
            '{ 0, -1, -2, -1,  0},
            '{-1, -2, 16, -2, -1},
            '{ 0, -1, -2, -1,  0},
            '{ 0,  0, -1,  0,  0}
        };
    end

    //data feeder
    logic data_valid_in;
    logic signed [7:0] pixel_in;
    logic [$clog2(TOTAL_PIXELS)-1:0] read_ptr;
    logic start;
    logic engine_done;

    //engine output
    logic [$clog2(OUTPUT_COUNT)-1:0] mem_wr_addr;
    logic signed [31:0] mem_wr_data;
    logic mem_wr_en;

    typedef enum { IDLE, RUN, DONE } state_t;
    state_t state;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            read_ptr <= 0;
            data_valid_in <= 0;
            start <= 0;
            pixel_in <= 0;
        end else begin
            case (state)
                IDLE: begin
                    //waits a few cycles then start
                    start <= 1;
                    state <= RUN;
                end

                RUN: begin
                    start <= 0; //pulse start
                    
                    //feed one pixel per cycle
                    if (read_ptr < TOTAL_PIXELS) begin
                        data_valid_in <= 1;
                        pixel_in <= image_rom[read_ptr];
                        read_ptr <= read_ptr + 1;
                    end else begin
                        data_valid_in <= 0;
                        //wait for engine to assert done
                        if (engine_done) state <= DONE;
                    end
                end

                DONE: begin
                    data_valid_in <= 0;
                end
            endcase
        end
    end


    conv_engine #( .MAPSIZE(MAPSIZE) ) DUT (
        .clk(clk),
        .rst(rst),
        .start(start),
        .data_valid_in(data_valid_in),
        .pixel_in(pixel_in),
        .weights(weights),
        .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data),
        .mem_wr_en(mem_wr_en),
        .all_done(engine_done)
    );

    logic error_latched;

    always_ff @(posedge clk) begin
        if (rst) begin
            error_latched <= 0;
        end else begin
            if (mem_wr_en) begin
                //compare the engine's output vs the golden
                if (mem_wr_data !== golden_rom[mem_wr_addr]) begin
                    error_latched <= 1;
                end
            end
        end
    end


    //LED 0 (Green) = Done
    //LED 1 (Red)   = Error found at any point
    assign led[0] = (state == DONE); 
    assign led[1] = error_latched;   

endmodule