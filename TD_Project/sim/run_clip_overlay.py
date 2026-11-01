from pathlib import Path
import subprocess,json
r=Path(__file__).resolve().parent
s='''onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_clip_overlay]} {vlib work_clip_overlay}
vlog -sv -work work_clip_overlay {*}[glob ../rtl/display/*.v] tb_clip_overlay.sv
vsim -c work_clip_overlay.tb_clip_overlay
run -all
quit -code 0 -f
'''
(r/'run_clip_overlay.do').write_text(s)
p=subprocess.run(['vsim','-c','-do','run_clip_overlay.do','-l','clip_overlay.log','-wlf','clip_overlay.wlf'],cwd=r,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=90)
log=(r/'clip_overlay.log').read_text(errors='replace')
ok=p.returncode==0 and 'TB_PASS' in log and '** Fatal:' not in log
result={'pass':ok,'exit_code':p.returncode,'summary':[s for s in log.splitlines() if 'TB_PASS' in s]}
(r/'clip_overlay_results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
if not ok:print(log[-3500:])
assert ok
