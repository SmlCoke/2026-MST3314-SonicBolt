# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Logic Library settings
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
lappend search_path ~/Desktop/Workspace/SMIC18/db ../scripts ../design
set_app_var target_library "slow.db S018V3EBCDSP_X8Y4D64_PR.db S018V3EBCDSP_X8Y4D80_PR.db S018V3EBCDSP_X8Y4D96_PR.db S018V3EBCDSP_X8Y4D112_PR.db S018V3EBCDSP_X8Y4D128_PR.db S018V3EBCDSP_X20Y4D64_PR.db S018V3EBCDSP_X64Y4D32_PR.db"
set_app_var link_library "* slow.db SP018W_V1p5_max.db S018V3EBCDSP_X8Y4D64_PR.db S018V3EBCDSP_X8Y4D80_PR.db S018V3EBCDSP_X8Y4D96_PR.db S018V3EBCDSP_X8Y4D112_PR.db S018V3EBCDSP_X8Y4D128_PR.db S018V3EBCDSP_X20Y4D64_PR.db S018V3EBCDSP_X64Y4D32_PR.db"
set_min_library slow.db -min_version fast.db
set_min_library SP018W_V1p5_max.db -min_version SP018W_V1p5_min.db

set_min_library S018V3EBCDSP_X8Y4D64_PR.db -none
set_min_library S018V3EBCDSP_X8Y4D80_PR.db -none
set_min_library S018V3EBCDSP_X8Y4D96_PR.db -none
set_min_library S018V3EBCDSP_X8Y4D112_PR.db -none
set_min_library S018V3EBCDSP_X8Y4D128_PR.db -none
set_min_library S018V3EBCDSP_X20Y4D64_PR.db -none
set_min_library S018V3EBCDSP_X64Y4D32_PR.db -none

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Physical Library settings
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
set mw_path "~/Desktop/Workspace/SMIC18/mw_lib"
set tech_file "~/Desktop/Workspace/SMIC18/tech/smic18_5lm.tf"
set tlup_map "~/Desktop/Workspace/SMIC18/tlup/smic018_5lm_map"
set tlup_max "~/Desktop/Workspace/SMIC18/tlup/smiclog018_5lm_cell_max.tluplus"
set tlup_min "~/Desktop/Workspace/SMIC18/tlup/smiclog018_5lm_cell_min.tluplus"
set verilog_file "../design/cnn_chip_clk_with_driving.v"
set sdc_file "../design/cnn_chip_clk_with_driving.sdc"

set_app_var sh_enable_page_mode false

source run_data_setup.tcl
source run_design_planning.tcl
source run_placement.tcl
source run_cts.tcl
source run_route.tcl
source run_finishing.tcl