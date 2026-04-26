# Script step 1 - Data Setup and Basic Flow
#
exec rm -rf ../cnn_chip.mw
#
############################################################
# Create Milkyway Design Library
############################################################
create_mw_lib ../cnn_chip.mw -open -technology $tech_file -mw_reference_library  "$mw_path/smic18_5ml $mw_path/SP018W_V1p5_5MT $mw_path/S018V3EBCDSP_X8Y4D64_PR $mw_path/S018V3EBCDSP_X8Y4D80_PR $mw_path/S018V3EBCDSP_X8Y4D96_PR $mw_path/S018V3EBCDSP_X8Y4D112_PR $mw_path/S018V3EBCDSP_X8Y4D128_PR $mw_path/S018V3EBCDSP_X20Y4D64_PR $mw_path/S018V3EBCDSP_X64Y4D32_PR"

############################################################
# Load the netlist, constraints and controls.
############################################################
import_designs $verilog_file -format verilog -top cnn_chip 
#read_verilog -top cnn_chip -allow_black_box $verilog_file 
############################################################
# Load TLU+ files
############################################################
set_tlu_plus_files -max_tluplus $tlup_max -min_tluplus $tlup_min -tech2itf_map  $tlup_map

check_library
check_tlu_plus_files
list_libs

source derive_pg.tcl
check_mv_design -power_nets

read_sdc $sdc_file
check_timing
report_timing_requirements
report_disable_timing
report_case_analysis
report_clock
report_clock -skew
redirect -tee ../reports/data_setup.timing { report_timing }

source opt_ctrl.tcl
source zic_timing.tcl
#exec cat zic.timing
#remove_ideal_network [get_ports scan_en]
save_mw_cel -as 1_datasetup
