# 1. Timing
redirect -tee ../reports/post_route_timing_max.rpt {
    report_timing -delay max -max_paths 20 -nworst 1
}
redirect -tee ../reports/post_route_timing_min.rpt {
    report_timing -delay min -max_paths 20 -nworst 1
}
redirect -tee ../reports/post_route_constraints.rpt {
    report_constraint -all
}

# 2. Area / QoR / resource usage
redirect -tee ../reports/post_route_qor.rpt {
    report_qor
}
redirect -tee ../reports/post_route_design_physical.rpt {
    report_design -physical
}
redirect -tee ../reports/post_route_route_resource.rpt {
    report_design_physical -route
}

# 3. Power
redirect -tee ../reports/post_route_power.rpt {
    report_power
}
redirect -tee ../reports/post_route_power_hier.rpt {
    report_power -hierarchy
}

# 4. IR drop / power rail
redirect -tee ../reports/post_route_ir_drop.rpt {
    analyze_fp_rail -nets {VDD VSS} -voltage_supply 1.98 -pad_masters {PVSS1W PVDD1W}
}

# 5. Congestion
redirect -tee ../reports/post_route_congestion.rpt {
    report_congestion
}

# 6. Design violations
redirect -tee ../reports/post_route_verify_zrt_route.rpt {
    verify_zrt_route
}
redirect -tee ../reports/post_route_verify_lvs.rpt {
    verify_lvs
}
redirect -tee ../reports/post_route_verify_pg_nets.rpt {
    verify_pg_nets
}
redirect -tee ../reports/post_route_check_legality.rpt {
    check_legality
}
