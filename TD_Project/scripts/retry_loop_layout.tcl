set root [file normalize [file join [file dirname [info script]] ..]]
set seed $env(CLIP_LAYOUT_SEED)
if {$seed ni {29 17}} {error "Only two scoped area-priority retries"}
set tag loop10r$seed
set gate_dir $root/build/campus_copy_map1_loop10
set build_dir $root/build/campus_copy_map1_$tag
if {[file exists $build_dir]} {error "Preserve prior layout result"}
file mkdir $build_dir
file copy $gate_dir/key_slideshow_gate.db $build_dir/key_slideshow_gate.db
cd $build_dir
import_db $build_dir/key_slideshow_gate.db
clear_sdc
read_sdc $root/constraints/hx4s20_key_slideshow.sdc
set_param place seed $seed
set_param place effort high
set_param place hfn_opt_effort high
set_param place opt_timing ultra
set_param place logic_level_opt on
set_param place post_place_opt ultra
set_param route fix_hold off
set_param route timing greedy
set_param route effort routability
place
update_timing -mode manhattan
report_timing_summary -file $build_dir/place.timing
route
fix_hold
update_timing -mode final
report_qor -step route -file $build_dir/route.qor
report_area -io_info -file $build_dir/route.area
report_timing_summary -file $build_dir/route.timing
export_db $build_dir/key_slideshow_route.db
set fd [open $build_dir/route.timing r]
set timing [read $fd]
close $fd
if {![regexp {SWNS: ([-0-9.]+)ns, STNS: ([-0-9.]+)ns} $timing -> sw st] ||
    ![regexp {HWNS: ([-0-9.]+)ns, HTNS: ([-0-9.]+)ns} $timing -> hw ht]} {error "Cannot parse timing"}
if {$sw < 0 || $hw < 0 || $st != 0 || $ht != 0} {
 puts "CANDIDATE_REJECTED: negative routed timing; no bitstream generated"
 exit 2
}
bitgen -bit $build_dir/campus_copy.bit
exit
