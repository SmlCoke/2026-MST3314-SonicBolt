# Create corners and P/G pads
create_cell {CornerLL CornerLR CornerTR CornerTL} PCORNERW
create_cell {vss1_l vss1_r vss1_t vss1_b} PVSS1W
create_cell {vdd1_l vdd1_r vdd1_t vdd1_b} PVDD1W
create_cell {vss2_l vss2_r vss2_t vss2_b} PVSS2W
create_cell {vdd2_l vdd2_r vdd2_t vdd2_b} PVDD2W

# Define corner pad locations
set_pad_physical_constraints -pad_name {CornerTL} -side 1
set_pad_physical_constraints -pad_name {CornerTR} -side 2
set_pad_physical_constraints -pad_name {CornerLR} -side 3
set_pad_physical_constraints -pad_name {CornerLL} -side 4

# Note:
# The synthesized netlist keeps 89 PIW inputs and 68 PO8W outputs as pad cells.
# The top-level port start is present in cnn_chip_clk_with_driving.v, but PIW_start
# is not preserved in the synthesized netlist, so it is intentionally not listed here.

# Left side
set_pad_physical_constraints -pad_name {PIW_clk} -side 1 -order 1
set_pad_physical_constraints -pad_name {PIW_rst_n} -side 1 -order 2
set_pad_physical_constraints -pad_name {PIW_img_wr_en} -side 1 -order 3
set_pad_physical_constraints -pad_name {PIW_img_wr_commit} -side 1 -order 4
set_pad_physical_constraints -pad_name {gen_piw_img_wr_addr[0].u_piw} -side 1 -order 5
set_pad_physical_constraints -pad_name {gen_piw_img_wr_addr[1].u_piw} -side 1 -order 6
set_pad_physical_constraints -pad_name {gen_piw_img_wr_addr[2].u_piw} -side 1 -order 7
set_pad_physical_constraints -pad_name {gen_piw_img_wr_addr[3].u_piw} -side 1 -order 8
set_pad_physical_constraints -pad_name {gen_piw_img_wr_addr[4].u_piw} -side 1 -order 9
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[0].u_piw} -side 1 -order 10
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[1].u_piw} -side 1 -order 11
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[2].u_piw} -side 1 -order 12
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[3].u_piw} -side 1 -order 13
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[4].u_piw} -side 1 -order 14
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[5].u_piw} -side 1 -order 15
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[6].u_piw} -side 1 -order 16
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[7].u_piw} -side 1 -order 17
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[8].u_piw} -side 1 -order 18
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[9].u_piw} -side 1 -order 19
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[10].u_piw} -side 1 -order 20
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[11].u_piw} -side 1 -order 21
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[12].u_piw} -side 1 -order 22
set_pad_physical_constraints -pad_name {vdd2_l} -side 1 -order 23
set_pad_physical_constraints -pad_name {vdd1_l} -side 1 -order 24
set_pad_physical_constraints -pad_name {vss1_l} -side 1 -order 25
set_pad_physical_constraints -pad_name {vss2_l} -side 1 -order 26
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[13].u_piw} -side 1 -order 27
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[14].u_piw} -side 1 -order 28
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[15].u_piw} -side 1 -order 29
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[16].u_piw} -side 1 -order 30
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[17].u_piw} -side 1 -order 31
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[18].u_piw} -side 1 -order 32
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[19].u_piw} -side 1 -order 33
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[20].u_piw} -side 1 -order 34
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[21].u_piw} -side 1 -order 35
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[22].u_piw} -side 1 -order 36
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[23].u_piw} -side 1 -order 37
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[24].u_piw} -side 1 -order 38
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[25].u_piw} -side 1 -order 39
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[26].u_piw} -side 1 -order 40
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[27].u_piw} -side 1 -order 41
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[28].u_piw} -side 1 -order 42
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[29].u_piw} -side 1 -order 43
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[30].u_piw} -side 1 -order 44
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[31].u_piw} -side 1 -order 45
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[32].u_piw} -side 1 -order 46
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[33].u_piw} -side 1 -order 47
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[34].u_piw} -side 1 -order 48
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[35].u_piw} -side 1 -order 49

# Top side
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[36].u_piw} -side 2 -order 1
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[37].u_piw} -side 2 -order 2
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[38].u_piw} -side 2 -order 3
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[39].u_piw} -side 2 -order 4
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[40].u_piw} -side 2 -order 5
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[41].u_piw} -side 2 -order 6
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[42].u_piw} -side 2 -order 7
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[43].u_piw} -side 2 -order 8
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[44].u_piw} -side 2 -order 9
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[45].u_piw} -side 2 -order 10
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[46].u_piw} -side 2 -order 11
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[47].u_piw} -side 2 -order 12
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[48].u_piw} -side 2 -order 13
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[49].u_piw} -side 2 -order 14
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[50].u_piw} -side 2 -order 15
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[51].u_piw} -side 2 -order 16
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[52].u_piw} -side 2 -order 17
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[53].u_piw} -side 2 -order 18
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[54].u_piw} -side 2 -order 19
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[55].u_piw} -side 2 -order 20
set_pad_physical_constraints -pad_name {vdd2_t} -side 2 -order 21
set_pad_physical_constraints -pad_name {vdd1_t} -side 2 -order 22
set_pad_physical_constraints -pad_name {vss1_t} -side 2 -order 23
set_pad_physical_constraints -pad_name {vss2_t} -side 2 -order 24
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[56].u_piw} -side 2 -order 25
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[57].u_piw} -side 2 -order 26
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[58].u_piw} -side 2 -order 27
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[59].u_piw} -side 2 -order 28
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[60].u_piw} -side 2 -order 29
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[61].u_piw} -side 2 -order 30
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[62].u_piw} -side 2 -order 31
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[63].u_piw} -side 2 -order 32
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[64].u_piw} -side 2 -order 33
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[65].u_piw} -side 2 -order 34
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[66].u_piw} -side 2 -order 35
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[67].u_piw} -side 2 -order 36
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[68].u_piw} -side 2 -order 37
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[69].u_piw} -side 2 -order 38
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[70].u_piw} -side 2 -order 39
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[71].u_piw} -side 2 -order 40
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[72].u_piw} -side 2 -order 41
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[73].u_piw} -side 2 -order 42
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[74].u_piw} -side 2 -order 43
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[75].u_piw} -side 2 -order 44
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[76].u_piw} -side 2 -order 45
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[77].u_piw} -side 2 -order 46
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[78].u_piw} -side 2 -order 47
set_pad_physical_constraints -pad_name {gen_piw_img_wr_row_data[79].u_piw} -side 2 -order 48

# Right side
set_pad_physical_constraints -pad_name {PO8W_busy} -side 3 -order 1
set_pad_physical_constraints -pad_name {PO8W_done} -side 3 -order 2
set_pad_physical_constraints -pad_name {PO8W_img_wr_ready} -side 3 -order 3
set_pad_physical_constraints -pad_name {PO8W_out_stream_valid} -side 3 -order 4
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[0].u_po8w} -side 3 -order 5
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[1].u_po8w} -side 3 -order 6
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[2].u_po8w} -side 3 -order 7
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[3].u_po8w} -side 3 -order 8
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[4].u_po8w} -side 3 -order 9
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[5].u_po8w} -side 3 -order 10
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[6].u_po8w} -side 3 -order 11
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[7].u_po8w} -side 3 -order 12
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[8].u_po8w} -side 3 -order 13
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[9].u_po8w} -side 3 -order 14
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[10].u_po8w} -side 3 -order 15
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[11].u_po8w} -side 3 -order 16
set_pad_physical_constraints -pad_name {vdd2_r} -side 3 -order 17
set_pad_physical_constraints -pad_name {vdd1_r} -side 3 -order 18
set_pad_physical_constraints -pad_name {vss1_r} -side 3 -order 19
set_pad_physical_constraints -pad_name {vss2_r} -side 3 -order 20
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[12].u_po8w} -side 3 -order 21
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[13].u_po8w} -side 3 -order 22
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[14].u_po8w} -side 3 -order 23
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[15].u_po8w} -side 3 -order 24
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[16].u_po8w} -side 3 -order 25
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[17].u_po8w} -side 3 -order 26
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[18].u_po8w} -side 3 -order 27
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[19].u_po8w} -side 3 -order 28
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[20].u_po8w} -side 3 -order 29
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[21].u_po8w} -side 3 -order 30
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[22].u_po8w} -side 3 -order 31
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[23].u_po8w} -side 3 -order 32
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[24].u_po8w} -side 3 -order 33
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[25].u_po8w} -side 3 -order 34
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[26].u_po8w} -side 3 -order 35
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[27].u_po8w} -side 3 -order 36
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[28].u_po8w} -side 3 -order 37
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[29].u_po8w} -side 3 -order 38

# Bottom side
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[30].u_po8w} -side 4 -order 1
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[31].u_po8w} -side 4 -order 2
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[32].u_po8w} -side 4 -order 3
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[33].u_po8w} -side 4 -order 4
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[34].u_po8w} -side 4 -order 5
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[35].u_po8w} -side 4 -order 6
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[36].u_po8w} -side 4 -order 7
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[37].u_po8w} -side 4 -order 8
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[38].u_po8w} -side 4 -order 9
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[39].u_po8w} -side 4 -order 10
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[40].u_po8w} -side 4 -order 11
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[41].u_po8w} -side 4 -order 12
set_pad_physical_constraints -pad_name {vdd2_b} -side 4 -order 13
set_pad_physical_constraints -pad_name {vdd1_b} -side 4 -order 14
set_pad_physical_constraints -pad_name {vss1_b} -side 4 -order 15
set_pad_physical_constraints -pad_name {vss2_b} -side 4 -order 16
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[42].u_po8w} -side 4 -order 17
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[43].u_po8w} -side 4 -order 18
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[44].u_po8w} -side 4 -order 19
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[45].u_po8w} -side 4 -order 20
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[46].u_po8w} -side 4 -order 21
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[47].u_po8w} -side 4 -order 22
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[48].u_po8w} -side 4 -order 23
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[49].u_po8w} -side 4 -order 24
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[50].u_po8w} -side 4 -order 25
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[51].u_po8w} -side 4 -order 26
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[52].u_po8w} -side 4 -order 27
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[53].u_po8w} -side 4 -order 28
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[54].u_po8w} -side 4 -order 29
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[55].u_po8w} -side 4 -order 30
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[56].u_po8w} -side 4 -order 31
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[57].u_po8w} -side 4 -order 32
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[58].u_po8w} -side 4 -order 33
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[59].u_po8w} -side 4 -order 34
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[60].u_po8w} -side 4 -order 35
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[61].u_po8w} -side 4 -order 36
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[62].u_po8w} -side 4 -order 37
set_pad_physical_constraints -pad_name {gen_po8w_out_stream_data[63].u_po8w} -side 4 -order 38
