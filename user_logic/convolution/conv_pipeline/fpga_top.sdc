# Define the 50 MHz clock (Period = 20ns)
create_clock -name clk -period 20.000 [get_ports {clk}]

# Automatically calculate clock uncertainty (jitter)
derive_clock_uncertainty

# Set Input/Output delays (Optional but good practice to silence warnings)
# We assume no external delay requirements for LEDs/Buttons for this simple project
set_false_path -from [get_ports {rst_n}]
set_false_path -to [get_ports {led[*]}]
