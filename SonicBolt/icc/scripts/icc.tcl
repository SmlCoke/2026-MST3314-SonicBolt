# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Logic Library settings
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
set script_dir [file dirname [file normalize [info script]]]
set icc_dir [file normalize [file join $script_dir ..]]
set repo_root [file normalize [file join $icc_dir ../..]]
set smic18_dir [file join $repo_root SMIC18]
set design_dir [file join $icc_dir design]
set work_dir [file join $icc_dir work]

file mkdir $work_dir
cd $work_dir

set sram_libs [list \
    S018V3EBCDSP_X20Y4D64_PR.db \
    S018V3EBCDSP_X64Y4D32_PR.db \
    S018V3EBCDSP_X8Y4D112_PR.db \
    S018V3EBCDSP_X8Y4D128_PR.db \
    S018V3EBCDSP_X8Y4D64_PR.db \
    S018V3EBCDSP_X8Y4D80_PR.db \
    S018V3EBCDSP_X8Y4D96_PR.db]

set std_libs [list slow.db]
set pad_libs [list SP018W_V1p5_max.db]
set target_library_list [concat $std_libs $sram_libs]
set link_library_list [concat $std_libs $pad_libs $sram_libs]

lappend search_path [file join $smic18_dir db] $script_dir $design_dir
set_app_var target_library $target_library_list
set_app_var link_library [concat "*" $link_library_list]
set_min_library slow.db -min_version fast.db
set_min_library SP018W_V1p5_max.db -min_version SP018W_V1p5_min.db

foreach sram_db $sram_libs {
    set_min_library $sram_db -none
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Physical Library settings
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
set mw_path [file join $smic18_dir mw_lib]
set mw_reference_libraries [list \
    [file join $mw_path smic18_5ml] \
    [file join $mw_path SP018W_V1p5_5MT] \
    [file join $mw_path S018V3EBCDSP_X20Y4D64_PR] \
    [file join $mw_path S018V3EBCDSP_X64Y4D32_PR] \
    [file join $mw_path S018V3EBCDSP_X8Y4D112_PR] \
    [file join $mw_path S018V3EBCDSP_X8Y4D128_PR] \
    [file join $mw_path S018V3EBCDSP_X8Y4D64_PR] \
    [file join $mw_path S018V3EBCDSP_X8Y4D80_PR] \
    [file join $mw_path S018V3EBCDSP_X8Y4D96_PR]]
set tech_file [file join $smic18_dir tech smic18_5lm.tf]
set tlup_map [file join $smic18_dir tlup smic018_5lm_map]
set tlup_max [file join $smic18_dir tlup smiclog018_5lm_cell_max.tluplus]
set tlup_min [file join $smic18_dir tlup smiclog018_5lm_cell_min.tluplus]
set verilog_file [file join $design_dir cnn_chip_clk_with_driving.v]
set sdc_file [file join $design_dir cnn_chip_clk_with_driving.sdc]

set_app_var sh_enable_page_mode false

source [file join $script_dir run_data_setup.tcl]
source [file join $script_dir run_design_planning.tcl]
source [file join $script_dir run_placement.tcl]
source [file join $script_dir run_cts.tcl]
source [file join $script_dir run_route.tcl]
# source [file join $script_dir run_finishing.tcl]
