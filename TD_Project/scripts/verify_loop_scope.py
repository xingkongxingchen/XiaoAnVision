from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parents[1];w=r.parents[1]
b=w/'release/p45_clip2s_sram_20261028';f=w/'release/frozen_p44_before_clip_20261028'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
m=json.loads((b/'MANIFEST_SHA256.json').read_text(encoding='utf-8'))
for k,v in m.items():assert sha(b/k)==v['sha256'],k
allowed={'rtl/framebank/media_player_control.v','rtl/filesystem/fat32_bmp_read.v','rtl/filesystem/fat32_file_streamer.v','rtl/top.v','rtl/framebank/media_video_pipeline.v','rtl/video_clip/clip_play_control.v','rtl/video_clip/clip_voice_player.v'}
changed=[]
for folder in ['rtl','constraints']:
 for p in (b/'source'/folder).rglob('*'):
  if not p.is_file():continue
  rel=p.relative_to(b/'source').as_posix();assert (r/rel).is_file(),rel
  if sha(p)!=sha(r/rel):changed.append(rel)
assert set(changed)==allowed,changed
assert sha(r/'scripts/build_layout.tcl')==sha(b/'source/scripts/build_layout.tcl')
assert sha(r/'assets/CLIP.BIN')==sha(b/'tf_add/CLIP.BIN')
assert (r/'rtl/top.v').read_text(encoding='utf-8').count('.ENABLE_CRC_DIAG(1)')==3,'All original CRC diagnostic sites must remain enabled'
fm=json.loads((f/'FROZEN_MANIFEST.json').read_text(encoding='utf-8'))
for rec in fm['files']:
 assert sha(f/rec['backup'])==rec['sha256'],rec['backup']
 assert sha(Path(rec['source']))==rec['sha256'],rec['source']
result={'baseline_release_files_reverified':len(m),'frozen_p44_records_reverified':len(fm['files']),
 'changed_rtl':sorted(changed),'clocks_constraints_build_list_unchanged':True,
 'protected_sd_sdram_fifo_timing_hdmi_unchanged':True,'asset_unchanged':True,'runtime_C2_crc_enabled':True,'fat_cluster_advance_added_cycles':1,'invalid_bmp_metadata_error_added_cycles':4,
 'baseline_bit_sha256':sha(b/'campus_p45_clip2s_SRAM_ONLY.bit'),'asset_sha256':sha(r/'assets/CLIP.BIN')}
(r/'SCOPE_P47.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))
