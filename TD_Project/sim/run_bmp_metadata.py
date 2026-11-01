from pathlib import Path
import subprocess,json
r=Path(__file__).resolve().parent
p=subprocess.run(['vsim','-c','-do','run_bmp_metadata.do','-l','bmp_metadata.log','-wlf','bmp_metadata.wlf'],cwd=r,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=90)
log=(r/'bmp_metadata.log').read_text(errors='replace')
result={'pass':p.returncode==0 and 'TB_PASS' in log and '** Fatal:' not in log,'exit_code':p.returncode,'summary':[s for s in log.splitlines() if 'TB_PASS' in s]}
(r/'bmp_metadata_results.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result));assert result['pass']
