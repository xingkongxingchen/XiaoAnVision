from pathlib import Path
import subprocess,struct,json,time
r=Path(__file__).resolve().parent
payload=(r.parent/'assets/CLIP.BIN').read_bytes()[512:512+1536000]
(r/'clip_words.hex').write_text(''.join(f'{w:08x}\n' for (w,) in struct.iter_unpack('<I',payload)),encoding='ascii')
s='''onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_clip_pipeline]} {vlib work_clip_pipeline}
vlog -sv -work work_clip_pipeline F:/qiansai_anlu/sim_release/common/al_map_lut.v {*}[glob ../rtl/framebank/*.v] {*}[glob ../rtl/control/*.v] {*}[glob ../rtl/video_clip/*.v] ../rtl/display/thumbnail_layout.v ../rtl/display/brightness_contrast_adjust.v tb_clip_pipeline.sv
vsim -c work_clip_pipeline.tb_clip_pipeline
run -all
quit -code 0 -f
'''
(r/'run_clip_pipeline.do').write_text(s)
t=time.time()
p=subprocess.run(['vsim','-c','-do','run_clip_pipeline.do','-l','clip_pipeline.log','-wlf','clip_pipeline.wlf'],cwd=r,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=900)
log=(r/'clip_pipeline.log').read_text(errors='replace')
ok=p.returncode==0 and 'TB_PASS' in log and '** Fatal:' not in log
result={'pass':ok,'exit_code':p.returncode,'seconds':time.time()-t,'summary':[s for s in log.splitlines() if 'TB_PASS' in s]}
(r/'clip_pipeline_results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
if not ok:print(log[-5000:])
assert ok
