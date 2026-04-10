###################################################################
# conv_tile_mac_row_mult timing SDC (no IO-pad driving constraints)
###################################################################
set sdc_version 2.1
set_units -time ns -resistance kOhm -capacitance pF -power mW -voltage V -current mA
set_wire_load_mode segmented

# ------------------------------------------------------------
# Clock
# ------------------------------------------------------------
# Start with a relaxed target for diagnosis.
# You can tighten this later (e.g. 10ns / 8ns / 5ns).
create_clock -name clk -period 20 [get_ports clk]
set_clock_uncertainty 0.2 [get_clocks clk]

# ------------------------------------------------------------
# Basic IO timing (no set_driving_cell IO-pad constraints)
# ------------------------------------------------------------
set_input_delay  2 -clock clk [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_output_delay 2 -clock clk [all_outputs]

# Optional electrical assumptions for cleaner optimization behavior
set_input_transition 0.2 [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_load 0.01 [all_outputs]
set_max_transition 3 [current_design]
