`timescale 1ns / 1ps

module tb_OneHotCalculator;

    // Inputs to the DUT (Device Under Test)
    reg Start;
    reg Clear;
    reg CLK_50;

    // Output from the DUT
    wire [7:0] LED_OUT;

    // Instantiate the module you want to test
    OneHotCalculator dut (
        .Start(Start),
        .Clear(Clear),
        .CLK_50(CLK_50),
        .LED_OUT(LED_OUT)
    );

    // 1. Clock Generation: Create a 50 MHz clock (20 ns period)
    initial begin
        CLK_50 = 0;
        forever #10 CLK_50 = ~CLK_50; // Toggles every 10 ns
    end

    // 2. Stimulus: Define the test sequence
    initial begin
        // Initialize inputs
        Start = 1'b0;
        Clear = 1'b0;
        #20;

        // Apply a reset pulse for two clock cycles
        Clear = 1'b1;
        #40;
        Clear = 1'b0;
        #20;

        // Pulse the Start signal for one clock cycle
        Start = 1'b1;
        #20;
        Start = 1'b0;

        // Wait for the calculation to complete (20 cycles)
        #400;

        // End the simulation
        $finish;
    end

endmodule