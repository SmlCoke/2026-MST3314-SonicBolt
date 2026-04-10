# ============================================================
# ZenSyn single-module synthesis script
# Top: conv_tile_mac_row_mult
# Purpose:
#   1) Isolate runtime bottleneck of row_mult
#   2) Avoid full-chip IO-pad style constraints
# ============================================================

# Resolve paths from script location, so this script works
# regardless of the current shell working directory.
set script_dir [file dirname [file normalize [info script]]]
set syn_test_dir [file dirname $script_dir]
set project_dir [file dirname $syn_test_dir]
set src_dir [file join $project_dir src]
set reports_dir [file join $syn_test_dir reports]
set outputs_dir [file join $syn_test_dir outputs]

# --------------------------
# Library / search setup
# --------------------------
# Keep both possible SMIC18 locations:
# 1) ../../SMIC18/*   (current repo layout)
# 2) ../../../SMIC18/* (server layout where SMIC18 is sibling)
set search_path "$search_path $src_dir [file join $src_dir conv] [file join $src_dir utils] [file join $project_dir SMIC18 lib] [file join $project_dir SMIC18 mem] [file join [file dirname $project_dir] SMIC18 lib] [file join [file dirname $project_dir] SMIC18 mem] $script_dir [file join $syn_test_dir work]"

# For single-module debugging, standard cell library is enough.
# If your environment requires IO/memory libs in link, append them here.
set target_lib "slow.lib"
set link_priority "* slow"

# --------------------------
# Read RTL
# --------------------------
read_design -format verilog [file join $src_dir conv conv_tile_mac_dot7_cell.v]
read_design -format verilog [file join $src_dir conv conv_tile_mac_row_mult.v]

# --------------------------
# Set top and link
# --------------------------
set current_design conv_tile_mac_row_mult
link_design

# NOTE:
# Do NOT use make_unique in this single-module timing diagnosis flow.
# make_unique is mainly useful in full-chip/large-hierarchy optimization.

# --------------------------
# Read timing constraint
# --------------------------
source [file join $script_dir row_mult.sdc]

# --------------------------
# Logic synthesis
# --------------------------
optimize

# --------------------------
# Reports
# --------------------------
analyze_constraint -all_violators > [file join $reports_dir row_mult_violators.rpt]
analyze_area > [file join $reports_dir row_mult_area.rpt]
analyze_timing > [file join $reports_dir row_mult_timing.rpt]

# --------------------------
# Output netlist / sdc
# --------------------------
write_design -format verilog -hierarchy -o [file join $outputs_dir conv_tile_mac_row_mult_syn.v]
write_sdc [file join $outputs_dir conv_tile_mac_row_mult_syn.sdc]
