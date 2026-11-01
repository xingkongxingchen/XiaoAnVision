from pathlib import Path
import subprocess,json,time
r=Path(__file__).resolve().parent
s='''onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_legacy_display]} {vlib work_legacy_display}
vlog -sv -work work_legacy_display F:/qiansai_anlu/sim_release/common/al_map_lut.v {*}[glob ../rtl/framebank/*.v] {*}[glob ../rtl/control/*.v] {*}[glob ../rtl/video_clip/*.v] ../rtl/display/thumbnail_layout.v ../rtl/display/brightness_contrast_adjust.v tb_legacy_display.sv
vsim -c work_legacy_display.tb_p43_pipeline -gQUICK=1 -gDIAG=1 -gINJECT=0
run -all
quit -code 0 -f
'''
(r/'run_legacy_display.do').write_text(s)
t=time.time()
p=subprocess.run(['vsim','-c','-do','run_legacy_display.do','-l','legacy_display.log','-wlf','legacy_display.wlf'],cwd=r,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=600)
log=(r/'legacy_display.log').read_text(errors='replace')
ok=p.returncode==0 and 'TB_PASS' in log and '** Fatal:' not in log
result={'pass':ok,'exit_code':p.returncode,'seconds':time.time()-t,'summary':[s for s in log.splitlines() if 'TB_PASS' in s]}
(r/'legacy_display_results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
if not ok:print(log[-3500:])
assert ok
