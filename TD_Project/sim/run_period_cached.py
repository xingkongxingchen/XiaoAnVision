from pathlib import Path
import subprocess,json
r=Path(__file__).resolve().parent
s='''onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_period_cached]} {vlib work_period_cached}
vlog -sv -work work_period_cached ../rtl/framebank/media_player_control.v reference_player_control.v tb_period_cached.sv
'''
results=[]
for i,(d,e,n) in enumerate([(0,0,5),(1,0,5),(1,1,5),(1,1,0)]):
 body=s+f'vsim -c work_period_cached.tb_period_cached -gDIRECT={d} -gEMERGENCY={e} -gDEFAULT_PERIOD={n}\nrun -all\nquit -code 0 -f\n'
 (r/f'run_period_cached{i}.do').write_text(body,encoding='utf-8')
 p=subprocess.run(['vsim','-c','-do',f'run_period_cached{i}.do','-l',f'period_cached{i}.log','-wlf',f'period_cached{i}.wlf'],cwd=r,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=60)
 log=(r/f'period_cached{i}.log').read_text(errors='replace');v={'case':i,'pass':p.returncode==0 and 'TB_PASS' in log and '** Fatal:' not in log,'summary':[x for x in log.splitlines() if 'TB_PASS' in x]};results.append(v);print(json.dumps(v),flush=True)
 if not v['pass']:print(log[-3000:])
(r/'period_cached_results.json').write_text(json.dumps(results,indent=2),encoding='utf-8');assert all(t['pass'] for t in results)
