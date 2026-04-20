# Library Setup
# Keep both possible SMIC18 locations in search_path:
# 1) ../../SMIC18/*   (current repo layout)
# 2) ../../../SMIC18/* (server layout where SMIC18 is sibling of project folder)
set search_path "$search_path ../rtl/cnn ../rtl/cnn/conv ../rtl/cnn/dwconv ../rtl/cnn/pwconv ../rtl/cnn/post_process ../rtl/cnn/utils ../scripts ../../SMIC18/lib ../../SMIC18/mem ../../../SMIC18/lib ../../../SMIC18/mem ../work"

# Standard cell + IO + SRAM macro timing libraries
# If you run worst-case timing closure, replace *_tt_1.8_25.lib with *_ss_1.62_125.lib.
set target_lib "slow.lib SP018W_V1p8_max.lib S018V3EBCDSP_X8Y4D64_PR_tt_1.8_25.lib S018V3EBCDSP_X8Y4D80_PR_tt_1.8_25.lib S018V3EBCDSP_X8Y4D96_PR_tt_1.8_25.lib S018V3EBCDSP_X8Y4D112_PR_tt_1.8_25.lib S018V3EBCDSP_X8Y4D128_PR_tt_1.8_25.lib S018V3EBCDSP_X20Y4D64_PR_tt_1.8_25.lib S018V3EBCDSP_X64Y4D32_PR_tt_1.8_25.lib"

set link_priority "* slow SP018W_V1p8_max S018V3EBCDSP_X8Y4D64_PR_tt_1.8_25 S018V3EBCDSP_X8Y4D80_PR_tt_1.8_25 S018V3EBCDSP_X8Y4D96_PR_tt_1.8_25 S018V3EBCDSP_X8Y4D112_PR_tt_1.8_25 S018V3EBCDSP_X8Y4D128_PR_tt_1.8_25 S018V3EBCDSP_X20Y4D64_PR_tt_1.8_25 S018V3EBCDSP_X64Y4D32_PR_tt_1.8_25"

# Read CNN RTL files (place these files under ../rtl/cnn with below structure)
read_design -format verilog ../rtl/cnn/utils/bias_pipe.v
read_design -format verilog ../rtl/cnn/utils/meta_pipe.v
read_design -format verilog ../rtl/cnn/utils/mult_cell.v
read_design -format verilog ../rtl/cnn/utils/relu_saturate.v
read_design -format verilog ../rtl/cnn/utils/rescale.v
read_design -format verilog ../rtl/cnn/utils/rescale_relu.v

read_design -format verilog ../rtl/cnn/conv/conv_tile_mac_reduce11_stage1_cell.v
read_design -format verilog ../rtl/cnn/conv/conv_tile_mac_reduce11_stage2_cell.v
read_design -format verilog ../rtl/cnn/conv/conv_tile_mac_row_mult.v
read_design -format verilog ../rtl/cnn/conv/conv_tile_mac_row_add.v
read_design -format verilog ../rtl/cnn/conv/conv_tile_mac.v
read_design -format verilog ../rtl/cnn/conv/conv_core.v
read_design -format verilog ../rtl/cnn/conv/conv_shared_input_buffer.v
read_design -format verilog ../rtl/cnn/conv/conv_param_store.v
read_design -format verilog ../rtl/cnn/conv/conv_subsystem.v

read_design -format verilog ../rtl/cnn/dwconv/dwconv_tile_mac_reduce3_cell.v
read_design -format verilog ../rtl/cnn/dwconv/dwconv_tile_mac_row_mult.v
read_design -format verilog ../rtl/cnn/dwconv/dwconv_tile_mac_row_add.v
read_design -format verilog ../rtl/cnn/dwconv/dwconv_tile_mac.v
read_design -format verilog ../rtl/cnn/dwconv/dwconv_core.v
read_design -format verilog ../rtl/cnn/dwconv/dwconv_param_store.v
read_design -format verilog ../rtl/cnn/dwconv/dwconv_subsystem.v

read_design -format verilog ../rtl/cnn/pwconv/pwconv_tile_mac_reduce8_cell.v
read_design -format verilog ../rtl/cnn/pwconv/pwconv_tile_mac_bank_mult.v
read_design -format verilog ../rtl/cnn/pwconv/pwconv_tile_mac_bank_accum.v
read_design -format verilog ../rtl/cnn/pwconv/pwconv_tile_mac_bias_add.v
read_design -format verilog ../rtl/cnn/pwconv/pwconv_tile_mac.v
read_design -format verilog ../rtl/cnn/pwconv/pwconv_input_buffer.v
read_design -format verilog ../rtl/cnn/pwconv/pwconv_param_store.v
read_design -format verilog ../rtl/cnn/pwconv/pwconv_core.v
read_design -format verilog ../rtl/cnn/pwconv/pwconv_subsystem.v

read_design -format verilog ../rtl/cnn/post_process/fc_bias_store.v
read_design -format verilog ../rtl/cnn/post_process/fc_frame_accum.v
read_design -format verilog ../rtl/cnn/post_process/fc_mac.v
read_design -format verilog ../rtl/cnn/post_process/fc_rescale.v
read_design -format verilog ../rtl/cnn/post_process/fc_saturate.v
read_design -format verilog ../rtl/cnn/post_process/fc_weight_sram.v
read_design -format verilog ../rtl/cnn/post_process/fc.v
read_design -format verilog ../rtl/cnn/post_process/maxpool.v
read_design -format verilog ../rtl/cnn/post_process/sigmoid.v
read_design -format verilog ../rtl/cnn/post_process/post_process_subsystem.v

read_design -format verilog ../rtl/cnn/cnn.v
read_design -format verilog ../rtl/cnn/cnn_chip.v

# Set Top Module
set current_design cnn_chip

link_design
make_unique

# Read Timing Constraint
source ../scripts/cnn.sdc

# Logic Synthesis
optimize

# Report
analyze_constraint -all_violators > ../reports/violators_clk_with_driving.rpt
analyze_area > ../reports/area_report_clk_with_driving.rpt
analyze_timing > ../reports/timing_report_clk_with_driving.rpt

# Output
write_design -format verilog -hierarchy -o ../outputs/cnn_chip_clk_with_driving.v
write_sdc ../outputs/cnn_chip_clk_with_driving.sdc
