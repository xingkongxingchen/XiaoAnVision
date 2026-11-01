set fpga [file normalize $env(XIAOAN_NATIVE_ROOT)]
set out [file join $fpga native_final]
if {[file exists $out]} {error "Preserve existing result: use a fresh build directory"}
file mkdir $out
cd $fpga
import_device eagle_s20.db -package EG4S20BG256
open_project -single_run ./XiaoAnVision.al
import_db ./XiaoAnVision_Runs/phy_1/XiaoAnVision_pr.db
# Explicit command is required: TD's internal route hold repair skips >90% slice use.
fix_hold
update_timing -mode final
report_qor -step route -file $out/route.qor
report_area -io_info -file $out/route.area
report_timing_summary -file $out/route.timing
export_db $out/XiaoAnVision_final.db
set fh [open $out/route.timing r]
set timing [read $fh]
close $fh
if {![regexp {SWNS: ([-0-9.]+)ns, STNS: ([-0-9.]+)ns} $timing -> sw st] ||
    ![regexp {HWNS: ([-0-9.]+)ns, HTNS: ([-0-9.]+)ns} $timing -> hw ht]} {error "Cannot parse routed timing"}
if {$sw < 0 || $hw < 0 || $st != 0 || $ht != 0} {error "POST_ROUTE_TIMING_REJECTED: no new bit generated"}
bitgen -bit $out/XiaoAnVision.bit
puts "NATIVE_AL_POST_ROUTE_HOLD_FIX_AND_TIMING_PASS"
exit
