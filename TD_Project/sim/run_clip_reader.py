from pathlib import Path
import subprocess,json,time,struct
r=Path(__file__).resolve().parent
payload=(r.parent/'assets/CLIP.BIN').read_bytes()[512:512+1536000]
(r/'clip_words.hex').write_text(''.join(f'{w:08x}\n' for (w,) in struct.iter_unpack('<I',payload)),encoding='ascii')
s='''onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_clip_reader]} {vlib work_clip_reader}
vlog -sv -work work_clip_reader F:/qiansai_anlu/sim_release/common/al_map_lut.v ../rtl/framebank/afifo_32_16_256.v ../rtl/framebank/fifo_prefetch_2.v ../rtl/framebank/media_frame_reader.v tb_clip_reader.sv
vsim -c work_clip_reader.tb_clip_reader
run -all
quit -code 0 -f
'''
(r/'run_clip_reader.do').write_text(s)
t=time.time()
p=subprocess.run(['vsim','-c','-do','run_clip_reader.do','-l','clip_reader.log','-wlf','clip_reader.wlf'],cwd=r,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=180)
log=(r/'clip_reader.log').read_text(errors='replace')
ok=p.returncode==0 and 'TB_PASS' in log and '** Fatal:' not in log
result={'pass':ok,'exit_code':p.returncode,'seconds':time.time()-t,'summary':[s for s in log.splitlines() if 'TB_PASS' in s]}
(r/'clip_reader_results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
if not ok:print(log[-3500:])
assert ok
