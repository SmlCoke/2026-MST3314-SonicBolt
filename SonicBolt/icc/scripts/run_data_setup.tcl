# Script step 1 - Data Setup and Basic Flow
#
exec rm -rf ../cnn_chip.mw
#
############################################################
# Create Milkyway Design Library
############################################################
create_mw_lib ../cnn_chip.mw -open -technology $tech_file -mw_reference_library $mw_reference_libraries

############################################################
# Load the netlist, constraints and controls.
############################################################
import_designs $verilog_file -format verilog -top cnn_chip 
############################################################
# Load TLU+ files
############################################################
set_tlu_plus_files -max_tluplus $tlup_max -min_tluplus $tlup_min -tech2itf_map  $tlup_map

check_library
check_tlu_plus_files
list_libs

source [file join $script_dir derive_pg.tcl]
check_mv_design -power_nets

read_sdc $sdc_file
check_timing
report_timing_requirements
report_disable_timing
report_case_analysis
report_clock
report_clock -skew
redirect -tee ../reports/data_setup.timing { report_timing }

source [file join $script_dir opt_ctrl.tcl]
source [file join $script_dir zic_timing.tcl]
#exec cat zic.timing
#remove_ideal_network [get_ports scan_en]
save_mw_cel -as 1_datasetup
