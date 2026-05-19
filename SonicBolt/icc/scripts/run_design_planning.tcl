#gui_set_current_task -name {Design Planning}

######################################################################
# Initialize Floorplan
######################################################################
# Create corners and P/G pads and define all pad cell locations:
source [file join $script_dir pad_cell_cons.tcl]
create_floorplan -core_utilization 0.35 -left_io2core 30.0 -bottom_io2core 30.0 -right_io2core 30.0 -top_io2core 30.0 

source [file join $script_dir derive_pg.tcl]
save_mw_cel -as 2_1_floorplan_init

create_fp_placement -timing_driven -no_hierarchy_gravity

## Create placement blockage around the macro to avoid DRC violations
##  1. You can create the placement blockage in the GUI:
##	i. In the menu, find "Floorplan" -- "Create placement blockage ..."
##	ii. In the layout window, use the mouse to create the placement blockage 
##  2. Or, you can use commands, for example:
	source [file join $script_dir create_macro_placement_blockage.tcl]
set_attribute [all_macro_cells] is_placed true
set_attribute [all_macro_cells] is_fixed true
save_mw_cel -as 2_2_floorplan_macro


### Build the power plan structure
source [file join $script_dir pns.tcl]
commit_fp_rail
preroute_instances
preroute_standard_cells -fill_empty_rows -remove_floating_pieces
analyze_fp_rail -nets {VDD VSS} -voltage_supply 1.98 -pad_masters {PVSS1W PVDD1W}
save_mw_cel -as 2_3_floorplan_pns

set_pnet_options -complete "METAL4 METAL5"
create_fp_placement -timing_driven -no_hierarchy_gravity
route_zrt_global

#Perform timing analysis
redirect -tee ../reports/floorplan.timing { report_timing }
save_mw_cel -as 2_4_floorplan_complete

remove_placement -object_type standard_cell
write_def -version 5.6 -placed -all_vias -blockages -routed_nets -specialnets -rows_tracks_gcells -output ../outputs/cnn_chip.def
