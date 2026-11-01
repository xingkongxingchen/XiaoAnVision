from pathlib import Path
import subprocess,json,re
r=Path(__file__).resolve().parent
top=(r.parent/'rtl/top.v').read_text(encoding='utf-8')
snippet=top.split('// PICTURE_KEY_STAGE_BEGIN',1)[1].split('// PICTURE_KEY_STAGE_END',1)[0]
assert '.short1(next_event && picture_key_context)' in top and '.short2(auto_toggle_event && picture_key_context)' in top
(r/'picture_context_stage.vh').write_text(snippet,encoding='utf-8')
cases={
 'adapter_narrow':('../rtl/filesystem/sd_sector_adapter.v reference_sd_sector_adapter.v tb_adapter_equivalence.sv','tb_adapter_equivalence'),
 'picture_key_context':('../rtl/control/period_setting_control.v ../rtl/control/slideshow_key_router.v ../rtl/control/dual_key_chord_router.v ../rtl/control/dual_key_long_hold_guard.v ../rtl/control/picture_adjust_control.v tb_picture_key_context.sv','tb_picture_key_context')
}
results=[]
for name,(files,tb) in cases.items():
 lib='work_'+name
 script=f'''onerror {{quit -code 1 -f}}
onbreak {{quit -code 1 -f}}
if {{![file exists {lib}]}} {{vlib {lib}}}
vlog -sv -work {lib} {files}
vsim -c {lib}.{tb}
run -all
quit -code 0 -f
'''
 (r/f'run_{name}.do').write_text(script)
 p=subprocess.run(['vsim','-c','-do',f'run_{name}.do','-l',f'{name}.log','-wlf',f'{name}.wlf'],cwd=r,capture_output=True,text=True,errors='replace',timeout=90)
 log=(r/f'{name}.log').read_text(errors='replace')
 ok=p.returncode==0 and 'TB_PASS' in log and '** Fatal:' not in log
 result={'case':name,'pass':ok,'summary':[line for line in log.splitlines() if 'TB_PASS' in line]}
 results.append(result);print(json.dumps(result),flush=True)
 if not ok:print(log[-4000:],flush=True)
(r/'timing_regressions.json').write_text(json.dumps(results,indent=2))
assert all(i['pass'] for i in results)
