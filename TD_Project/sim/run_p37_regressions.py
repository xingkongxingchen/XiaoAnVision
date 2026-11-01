from pathlib import Path
import os,subprocess,json
r=Path(__file__).resolve().parent
cases=[('finish0','run_parser_finish.do',{'FINISH_SCALE':'0'}),
       ('finish1','run_parser_finish.do',{'FINISH_SCALE':'1'}),
       ('header0','run_header_bounds.do',{'HEADER_SCALE':'0'}),
       ('header1','run_header_bounds.do',{'HEADER_SCALE':'1'}),
       ('timer0','run_parser_timeouts.do',{'TIMER_CASE':'0'}),
       ('timer1','run_parser_timeouts.do',{'TIMER_CASE':'1'}),
       ('preload0','run_scale_preload.do',{'PRELOAD_FULL':'0','PRELOAD_DIAG':'0'}),
       ('preload1','run_scale_preload.do',{'PRELOAD_FULL':'0','PRELOAD_DIAG':'1'})]
results=[]
for name,script,settings in cases:
 p=subprocess.run(['G:/quartus/modelsim_ase/win32aloem/vsim.exe','-c','-do',script,'-l',f'p37_{name}.log','-wlf',f'p37_{name}.wlf'],cwd=r,env=dict(os.environ,**settings),capture_output=True,text=True,errors='replace',timeout=300)
 log=(r/f'p37_{name}.log').read_text(errors='replace')
 ok=p.returncode==0 and 'TB_PASS' in log and '** Fatal:' not in log
 result={'case':name,'pass':ok,'exit_code':p.returncode,'summary':[l for l in log.splitlines()if 'TB_PASS' in l]}
 results.append(result);print(json.dumps(result),flush=True)
 if not ok:print(p.stdout[-4500:],flush=True);break
(r/'p37_regressions.json').write_text(json.dumps(results,indent=2))
assert len(results)==len(cases) and all(i['pass']for i in results)
