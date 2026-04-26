##########################################################################################
# Version: C-2009.06 (Jun 29th, 2009)
# Copyright (C) 2007-2009 Synopsys, Inc. All rights reserved.
##########################################################################################


echo "\tLoading :\t [info script]"

# Placement Common Session Options - set in all sessions

## Set Min/Max Routing Layers
#if { $MAX_ROUTING_LAYER != ""} {set_ignored_layers -max_routing_layer $MAX_ROUTING_LAYER}
#if { $MIN_ROUTING_LAYER != ""} {set_ignored_layers -min_routing_layer $MIN_ROUTING_LAYER}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Placement keepout variable settings
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
set_app_var physopt_hard_keepout_distance 5
set_app_var placer_soft_keepout_channel_width 15

## Set PNET Options to control cel placement around P/G straps 
remove_pnet_options
set_pnet_options -partial {METAL2 METAL3 METAL4}
report_pnet_options

## C4: 使能 enhanced router 改善拥塞分析
echo "SCRIPT-Info : Enabling Global Router during placement"
set_app_var placer_enable_enhanced_router true

## C4: 设置拥塞驱动的最大利用率
set_congestion_options -max_util 0.80
