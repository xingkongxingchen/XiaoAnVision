from pathlib import Path
import subprocess,json
r=Path(__file__).resolve().parent
p=subprocess.run(['vsim','-c','-do','run_voice_restart.do','-l','voice_restart_fixed.log','-wlf','voice_restart_fixed.wlf'],cwd=r,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=60)
log=(r/'voice_restart_fixed.log').read_text(errors='replace')
result={'pass':p.returncode==0 and 'TB_PASS' in log and '** Fatal:' not in log,'exit_code':p.returncode,'summary':[s for s in log.splitlines() if 'TB_PASS' in s]}
(r/'voice_restart_results.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result));assert result['pass']
