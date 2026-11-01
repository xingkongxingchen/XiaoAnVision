from pathlib import Path
import subprocess,json,time
r=Path(__file__).resolve().parent
data=(r.parent/'assets/CLIP.BIN').read_bytes()
(r/'clip_asset_bytes.hex').write_text(''.join(f'{b:02x}\n' for b in data),encoding='ascii')
s='''onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file exists work_clip_boot]} {vlib work_clip_boot}
vlog -sv -work work_clip_boot {*}[glob ../rtl/video_clip/*.v] {*}[glob ../rtl/filesystem/*.v] ../rtl/framebank/media_sdram_write_cdc.v ../rtl/control/reset_sync.v ../rtl/control/sync_2ff.v ../rtl/audio/dual_fat32_pcm_source.v ../rtl/audio/fat32_loop_stream.v ../rtl/audio/wav_stream_player.v tb_clip_boot.sv
vsim -c work_clip_boot.tb_clip_boot
run -all
quit -code 0 -f
'''
(r/'run_clip_boot.do').write_text(s)
t=time.time()
p=subprocess.run(['vsim','-c','-do','run_clip_boot.do','-l','clip_boot.log','-wlf','clip_boot.wlf'],cwd=r,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=600)
log=(r/'clip_boot.log').read_text(errors='replace')
ok=p.returncode==0 and 'TB_PASS' in log and '** Fatal:' not in log
result={'pass':ok,'exit_code':p.returncode,'seconds':time.time()-t,'summary':[s for s in log.splitlines() if 'TB_PASS' in s or 'CLIP_BOOT_PASS' in s]}
(r/'clip_boot_results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
if not ok:print(log[-4000:])
assert ok
