set fpga [file normalize $env(XIAOAN_NATIVE_ROOT)]
cd $fpga
import_device eagle_s20.db -package EG4S20BG256
open_project ./XiaoAnVision.al
launch_runs syn_1 -jobs 1
wait_run syn_1 -quiet
launch_runs phy_1 -step route -jobs 1
wait_run phy_1 -quiet
if {![file exists ./XiaoAnVision_Runs/phy_1/XiaoAnVision_pr.db]} {error "Native routed database was not generated"}
close_project
puts "NATIVE_AL_SYNTHESIS_PLACE_ROUTE_FINISHED"
exit
