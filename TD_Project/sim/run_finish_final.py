from pathlib import Path
import os,subprocess,json
r=Path(__file__).resolve().parent
out=[]
for scale in (0,1):
 logname=f'p37_finish{scale}_final.log'
 p=subprocess.run(['G:/quartus/modelsim_ase/win32aloem/vsim.exe','-c','-do','run_parser_finish.do','-l',logname,'-wlf',f'p37_finish{scale}_final.wlf'],cwd=r,env=dict(os.environ,FINISH_SCALE=str(scale)),capture_output=True,text=True,timeout=60)
 s=(r/logname).read_text(errors='replace')
 ok=p.returncode==0 and 'TB_PASS P37 parser completion' in s and '** Fatal:' not in s
 out.append({'scale':scale,'pass':ok,'log':logname,'summary':[l for l in s.splitlines()if 'TB_PASS' in l]})
 print(json.dumps(out[-1]),flush=True)
 if not ok:print(p.stdout[-3000:]);break
(r/'p37_finish_final.json').write_text(json.dumps(out,indent=2))
assert len(out)==2 and all(i['pass']for i in out)
