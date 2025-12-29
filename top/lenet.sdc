# Create a 50MHz clock on port 'clk' (Period = 20ns)
create_clock -name clk -period 20.000 [get_ports {clk}]

# Automatically constrain generated clocks (if any)
derive_pll_clocks

# Handle uncertainties
derive_clock_uncertainty
