from pathlib import Path
import subprocess,json
r=Path(__file__).resolve().parent
subprocess.run(['python',str(r/'make_clip_fixtures.py')],check=True)
cases=['control','control_collision','scaler','voice','preload']
results=[]
for name in cases:
 base='control' if name=='control_collision' else name
 options='-gFRAME_PERIOD=1000' if name=='control_collision' else ''
 lib='work_clip_'+name
 script=f'''onerror {{quit -code 1 -f}}
onbreak {{quit -code 1 -f}}
if {{![file exists {lib}]}} {{vlib {lib}}}
vlog -sv -work {lib} {{*}}[glob ../rtl/video_clip/*.v] ../rtl/filesystem/fat32_file_streamer.v tb_clip_{base}.sv
vsim -c {lib}.tb_clip_{base} {options}
run -all
quit -code 0 -f
'''
 (r/f'run_clip_{name}.do').write_text(script)
 p=subprocess.run(['vsim','-c','-do',f'run_clip_{name}.do','-l',f'clip_{name}.log','-wlf',f'clip_{name}.wlf'],cwd=r,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=180)
 log=(r/f'clip_{name}.log').read_text(errors='replace')
 ok=p.returncode==0 and 'TB_PASS' in log and '** Fatal:' not in log
 result={'case':name,'pass':ok,'exit_code':p.returncode,'summary':[s for s in log.splitlines() if 'TB_PASS' in s]}
 results.append(result);print(json.dumps(result),flush=True)
 if not ok:print(log[-4000:],flush=True)
(r/'clip_unit_results.json').write_text(json.dumps(results,indent=2))
assert all(i['pass'] for i in results)
