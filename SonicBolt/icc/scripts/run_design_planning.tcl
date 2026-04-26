#gui_set_current_task -name {Design Planning}

######################################################################
# Initialize Floorplan
######################################################################
# Create corners and P/G pads and define all pad cell locations:
source pad_cell_cons.tcl
#initialize_floorplan -core_utilization 0.8 -left_io2core 30.0 -bottom_io2core 30.0 -right_io2core 30.0 -top_io2core 30.0
create_floorplan -core_utilization 0.48 -left_io2core 30.0 -bottom_io2core 30.0 -right_io2core 30.0 -top_io2core 30.0 
#-control_type width_and_height -core_width 1500 -core_height 500

source derive_pg.tcl
save_mw_cel -as 2_1_floorplan_init

# move_objects -to {250 250} [get_cells {inst_cnn/conv_inst/u_frame_store_ping}]
# move_objects -to {600 250} [get_cells {inst_cnn/conv_inst/u_frame_store_pong}]
# move_objects -to {950 250} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[0].u_weight_bank_lo}]
# move_objects -to {1300 250} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[0].u_weight_bank_hi}]
# move_objects -to {250 430} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[1].u_weight_bank_lo}]
# move_objects -to {600 430} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[1].u_weight_bank_hi}]
# move_objects -to {950 430} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[2].u_weight_bank_lo}]
# move_objects -to {1300 430} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[2].u_weight_bank_hi}]
# move_objects -to {250 610} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[3].u_weight_bank_lo}]
# move_objects -to {600 610} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[3].u_weight_bank_hi}]
# move_objects -to {950 610} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[4].u_weight_bank_lo}]
# move_objects -to {1300 610} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[4].u_weight_bank_hi}]
# move_objects -to {250 790} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[5].u_weight_bank_lo}]
# move_objects -to {600 790} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[5].u_weight_bank_hi}]
# move_objects -to {950 790} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[6].u_weight_bank_lo}]
# move_objects -to {1300 790} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[6].u_weight_bank_hi}]
# move_objects -to {250 970} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[7].u_weight_bank_lo}]
# move_objects -to {600 970} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[7].u_weight_bank_hi}]
# move_objects -to {950 970} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[8].u_weight_bank_lo}]
# move_objects -to {1300 970} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[8].u_weight_bank_hi}]
# move_objects -to {250 1150} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[9].u_weight_bank_lo}]
# move_objects -to {600 1150} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[9].u_weight_bank_hi}]
# move_objects -to {950 1150} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[10].u_weight_bank_lo}]
# move_objects -to {1300 1150} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[10].u_weight_bank_hi}]
# move_objects -to {250 1330} [get_cells {inst_cnn/conv_inst/u_conv_param_store/u_bias_bank}]
# move_objects -to {600 1330} [get_cells {inst_cnn/dwconv_inst/u_dwconv_param_store/g_weight_bank[0].u_weight_bank}]
# move_objects -to {950 1330} [get_cells {inst_cnn/dwconv_inst/u_dwconv_param_store/g_weight_bank[1].u_weight_bank}]
# move_objects -to {1300 1330} [get_cells {inst_cnn/dwconv_inst/u_dwconv_param_store/g_weight_bank[2].u_weight_bank}]
# move_objects -to {250 1510} [get_cells {inst_cnn/dwconv_inst/u_dwconv_param_store/u_bias_bank}]
# move_objects -to {600 1510} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/g_weight_bank[0].u_weight_bank}]
# move_objects -to {950 1510} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/g_weight_bank[1].u_weight_bank}]
# move_objects -to {1300 1510} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/g_weight_bank[2].u_weight_bank}]
# move_objects -to {250 1690} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/g_weight_bank[3].u_weight_bank}]
# move_objects -to {600 1690} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/g_weight_bank[4].u_weight_bank}]
# move_objects -to {950 1690} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/g_weight_bank[5].u_weight_bank}]
# move_objects -to {1300 1690} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/g_weight_bank[6].u_weight_bank}]
# move_objects -to {250 1870} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/g_weight_bank[7].u_weight_bank}]
# move_objects -to {600 1870} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/u_bias_bank}]
# move_objects -to {950 1870} [get_cells {inst_cnn/post_process_inst/u_fc_weight_sram/u_fc_weight_sram}]
# move_objects -to {1300 1870} [get_cells {inst_cnn/post_process_inst/u_sigmoid/u_sigmoid_lut_sram}]

## Create placement blockage around the macro to avoid DRC violations
##  1. You can create the placement blockage in the GUI:
##	i. In the menu, find "Floorplan" -- "Create placement blockage ..."
##	ii. In the layout window, use the mouse to create the placement blockage 
##  2. Or, you can use commands, for example:
	source create_macro_placement_blockage.tcl
set_attribute [all_macro_cells] is_placed true
set_attribute [all_macro_cells] is_fixed true
save_mw_cel -as 2_2_floorplan_macro


### Build the power plan structure
source pns.tcl
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
