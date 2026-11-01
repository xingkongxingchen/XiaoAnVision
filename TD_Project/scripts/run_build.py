from pathlib import Path
import os,subprocess,json,sys,time,hashlib
root=Path(__file__).resolve().parents[1]
tag=sys.argv[1] if len(sys.argv)>1 else 'clip01'
assert tag.isalnum()
log=root/f'build_{tag}.log'
assert not log.exists()
seed=int(sys.argv[2]) if len(sys.argv)>2 else 29
assert seed in (29,23,17)
mode=sys.argv[3] if len(sys.argv)>3 else 'balance_explore'
assert mode in ('balance_explore','area_prior','auto')
env=dict(os.environ,COPY_MAP_MODE=mode,COPY_BUILD_TAG=tag,COPY_PLACE_SEED=str(seed))
t=time.time()
inputs=list((root/'rtl').rglob('*.v'))+list((root/'constraints').glob('*'))+[root/'scripts/build_layout.tcl']
snapshot={p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs if p.is_file()}
(root/f'build_{tag}_source.json').write_text(json.dumps(snapshot,indent=2),encoding='utf-8')
with log.open('wb') as f:
 p=subprocess.run(['F:/qiansai_anlu/bin/td_commands_prompt.exe'],input=b'if {[catch {source scripts/build_layout.tcl} err]} {puts "BUILD_FAILED: $err"; exit 1}\nexit\n',cwd=root,env=env,stdout=f,stderr=subprocess.STDOUT)
changed=[rel for rel,h in snapshot.items() if hashlib.sha256((root/rel).read_bytes()).hexdigest()!=h]
result={'tag':tag,'seed':seed,'map_mode':mode,'map_strategy':int(env.get('COPY_MAP_STRATEGY','1')),'pack_effort':env.get('COPY_PACK_EFFORT','high'),'exit_code':p.returncode,'seconds':time.time()-t,'log':str(log),'source_changed_during_build':changed}
(root/f'build_{tag}.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result))
print(log.read_text(errors='replace')[-3500:])
sys.exit(p.returncode)
