#gui_set_current_task -name {Design Planning}

######################################################################
# Initialize Floorplan
######################################################################
# Create corners and P/G pads and define all pad cell locations:
source pad_cell_cons.tcl
#initialize_floorplan -core_utilization 0.8 -left_io2core 30.0 -bottom_io2core 30.0 -right_io2core 30.0 -top_io2core 30.0
# C1: 提高 core 利用率并增大 io2core 间距，为 macro 布局留出布线空间
create_floorplan -core_utilization 0.55 -left_io2core 40.0 -bottom_io2core 40.0 -right_io2core 40.0 -top_io2core 40.0
#-control_type width_and_height -core_width 1500 -core_height 500

source derive_pg.tcl
save_mw_cel -as 2_1_floorplan_init

# C3: Macro 布局按数据流分组
#  左列 (x≈200): conv SRAMs
#  中列 (x≈900): dwconv + pwconv SRAMs
#  右列 (x≈1600): post_process SRAMs

# ---- 左列: Conv 子系统 SRAM ----
move_objects -to {200 200} [get_cells {inst_cnn/conv_inst/u_frame_store_ping}]
move_objects -to {400 200} [get_cells {inst_cnn/conv_inst/u_frame_store_pong}]
move_objects -to {200 380} [get_cells {inst_cnn/conv_inst/u_conv_param_store/u_bias_bank}]
move_objects -to {200 560} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[0].u_weight_bank_lo}]
move_objects -to {400 560} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[0].u_weight_bank_hi}]
move_objects -to {200 740} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[1].u_weight_bank_lo}]
move_objects -to {400 740} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[1].u_weight_bank_hi}]
move_objects -to {200 920} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[2].u_weight_bank_lo}]
move_objects -to {400 920} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[2].u_weight_bank_hi}]
move_objects -to {200 1100} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[3].u_weight_bank_lo}]
move_objects -to {400 1100} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[3].u_weight_bank_hi}]
move_objects -to {200 1280} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[4].u_weight_bank_lo}]
move_objects -to {400 1280} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[4].u_weight_bank_hi}]
move_objects -to {200 1460} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[5].u_weight_bank_lo}]
move_objects -to {400 1460} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[5].u_weight_bank_hi}]
move_objects -to {200 1640} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[6].u_weight_bank_lo}]
move_objects -to {400 1640} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[6].u_weight_bank_hi}]
move_objects -to {200 1820} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[7].u_weight_bank_lo}]
move_objects -to {400 1820} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[7].u_weight_bank_hi}]
move_objects -to {200 2000} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[8].u_weight_bank_lo}]
move_objects -to {400 2000} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[8].u_weight_bank_hi}]
move_objects -to {200 2180} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[9].u_weight_bank_lo}]
move_objects -to {400 2180} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[9].u_weight_bank_hi}]
move_objects -to {200 2360} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[10].u_weight_bank_lo}]
move_objects -to {400 2360} [get_cells {inst_cnn/conv_inst/u_conv_param_store/g_weight_bank[10].u_weight_bank_hi}]

# ---- 中列: DWConv + PWConv 子系统 SRAM ----
move_objects -to {900 200} [get_cells {inst_cnn/dwconv_inst/u_dwconv_param_store/g_weight_bank[0].u_weight_bank}]
move_objects -to {900 380} [get_cells {inst_cnn/dwconv_inst/u_dwconv_param_store/g_weight_bank[1].u_weight_bank}]
move_objects -to {900 560} [get_cells {inst_cnn/dwconv_inst/u_dwconv_param_store/g_weight_bank[2].u_weight_bank}]
move_objects -to {900 740} [get_cells {inst_cnn/dwconv_inst/u_dwconv_param_store/u_bias_bank}]
move_objects -to {900 920} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/g_weight_bank[0].u_weight_bank}]
move_objects -to {900 1100} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/g_weight_bank[1].u_weight_bank}]
move_objects -to {900 1280} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/g_weight_bank[2].u_weight_bank}]
move_objects -to {900 1460} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/g_weight_bank[3].u_weight_bank}]
move_objects -to {900 1640} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/g_weight_bank[4].u_weight_bank}]
move_objects -to {900 1820} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/g_weight_bank[5].u_weight_bank}]
move_objects -to {900 2000} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/g_weight_bank[6].u_weight_bank}]
move_objects -to {900 2180} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/g_weight_bank[7].u_weight_bank}]
move_objects -to {900 2360} [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/u_bias_bank}]

# ---- 右列: Post-Process 子系统 SRAM ----
move_objects -to {1600 200} [get_cells {inst_cnn/post_process_inst/u_fc_weight_sram/u_fc_weight_sram}]
move_objects -to {1600 380} [get_cells {inst_cnn/post_process_inst/u_sigmoid/u_sigmoid_lut_sram}]

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
