# Create corners and P/G pads
create_cell {CornerLL CornerLR CornerTR CornerTL} PCORNERW
create_cell {vss1_l vss1_r vss1_t vss1_b} PVSS1W
create_cell {vdd1_l vdd1_r vdd1_t vdd1_b} PVDD1W
create_cell {vss2_l vss2_r vss2_t vss2_b} PVSS2W
create_cell {vdd2_l vdd2_r vdd2_t vdd2_b} PVDD2W

proc apply_pad_constraints {side pads} {
    set order 1
    foreach pad $pads {
        set_pad_physical_constraints -pad_name $pad -side $side -order $order
        incr order
    }
}

# Define corner pad locations
set_pad_physical_constraints -pad_name CornerTL -side 1
set_pad_physical_constraints -pad_name CornerTR -side 2
set_pad_physical_constraints -pad_name CornerLR -side 3
set_pad_physical_constraints -pad_name CornerLL -side 4

# Left side: control, input address, and lower input data bits
set left_pads {PIW_clk PIW_rst_n PIW_img_wr_en PIW_img_wr_commit}
for {set i 0} {$i < 5} {incr i} {
    lappend left_pads [format {gen_piw_img_wr_addr[%d].u_piw} $i]
}
for {set i 0} {$i < 40} {incr i} {
    lappend left_pads [format {gen_piw_img_wr_row_data[%d].u_piw} $i]
}
lappend left_pads vdd2_l vdd1_l vss1_l vss2_l
apply_pad_constraints 1 $left_pads

# Top side: upper input data bits
set top_pads {}
for {set i 40} {$i < 80} {incr i} {
    lappend top_pads [format {gen_piw_img_wr_row_data[%d].u_piw} $i]
}
lappend top_pads vdd2_t vdd1_t vss1_t vss2_t
apply_pad_constraints 2 $top_pads

# Right side: status outputs and lower output data bits
set right_pads {PO8W_busy PO8W_done PO8W_img_wr_ready PO8W_out_stream_valid}
for {set i 0} {$i < 32} {incr i} {
    lappend right_pads [format {gen_po8w_out_stream_data[%d].u_po8w} $i]
}
lappend right_pads vdd2_r vdd1_r vss1_r vss2_r
apply_pad_constraints 3 $right_pads

# Bottom side: upper output data bits
set bottom_pads {}
for {set i 32} {$i < 64} {incr i} {
    lappend bottom_pads [format {gen_po8w_out_stream_data[%d].u_po8w} $i]
}
lappend bottom_pads vdd2_b vdd1_b vss1_b vss2_b
apply_pad_constraints 4 $bottom_pads
