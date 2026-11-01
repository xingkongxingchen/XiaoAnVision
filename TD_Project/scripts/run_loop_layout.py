from pathlib import Path
import os,subprocess,json,hashlib,sys,time
r=Path(__file__).resolve().parents[1];seed=int(sys.argv[1]);assert seed in (29,17)
tag=f'loop10r{seed}';assert not (r/f'build_{tag}.log').exists()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
s=json.loads((r/'build_loop10_source.json').read_text(encoding='utf-8'))
assert all(sha(r/k)==v for k,v in s.items())
(r/f'build_{tag}_source.json').write_text(json.dumps(s,indent=2),encoding='utf-8')
t=time.time()
with (r/f'build_{tag}.log').open('wb') as f:
 p=subprocess.run(['F:/qiansai_anlu/bin/td_commands_prompt.exe'],input=b'if {[catch {source scripts/retry_loop_layout.tcl} err]} {puts "BUILD_FAILED: $err"; exit 1}\nexit\n',cwd=r,env=dict(os.environ,CLIP_LAYOUT_SEED=str(seed)),stdout=f,stderr=subprocess.STDOUT)
result={'tag':tag,'seed':seed,'map_mode':'area_prior','exit_code':p.returncode,'seconds':time.time()-t,'source_changed_during_build':[k for k,v in s.items() if sha(r/k)!=v],'parent_gate_tag':'loop10','gate_sha256':sha(r/'build/campus_copy_map1_loop10/key_slideshow_gate.db')}
(r/f'build_{tag}.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result));print((r/f'build_{tag}.log').read_text(errors='replace')[-1000:]);sys.exit(p.returncode)
