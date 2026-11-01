from pathlib import Path
import hashlib,json,re,shutil,subprocess,sys,zipfile,datetime
r=Path(__file__).resolve().parents[1];w=r.parents[1]
tag=sys.argv[1];out=json.loads((r/f'build_{tag}.json').read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:json.loads(p.read_text(encoding='utf-8'))
assert out['exit_code']==0 and not out['source_changed_during_build']
snapshot=read(r/f'build_{tag}_source.json')
assert all(sha(r/k)==v for k,v in snapshot.items()),'Compiled source drift'
subprocess.run([sys.executable,str(r/'scripts/verify_loop_scope.py')],check=True)
scope=read(r/'SCOPE_P47.json')
mode=out['map_mode'];build=r/'build'/(f"campus_copy_map{out.get('map_strategy',1)}"+('' if mode=='area_prior' else '_'+mode)+'_'+tag)
timing=(build/'route.timing').read_text(errors='replace')
sw,st=map(float,re.search(r'SWNS: ([-\d.]+)ns, STNS: ([-\d.]+)ns',timing).groups())
hw,ht=map(float,re.search(r'HWNS: ([-\d.]+)ns, HTNS: ([-\d.]+)ns',timing).groups())
assert sw>=0 and hw>=0 and st==ht==0
area=(build/'route.area').read_text(errors='replace');resources={}
for k in ['lut','reg','bram','dsp','pll']:
 a,b=map(int,re.search(rf'^#{k}\s+(\d+)\s+out of\s+(\d+)',area,re.M).groups());assert a<=b
 resources[k]={'used':a,'total':b}
units=read(r/'sim/clip_unit_results.json');assert len(units)==5 and all(t['pass'] for t in units)
pipeline=read(r/'sim/clip_pipeline_results.json');assert pipeline['pass']
voice_restart=read(r/'sim/voice_restart_results.json');assert voice_restart['pass']
file_cursor=read(r/'sim/file_cursor_equivalence_results.json');assert file_cursor['pass']
boot=read(r/'sim/clip_boot_results.json');assert boot['pass']
metadata=read(r/'sim/bmp_metadata_results.json');assert metadata['pass']
parser_regressions=read(r/'sim/p44_regressions.json');assert len(parser_regressions)==8 and all(t['pass'] for t in parser_regressions)
provenance=read(r/'TEST_PROVENANCE.json')
period_cached=read(r/'sim/period_cached_results.json');assert len(period_cached)==4 and all(t['pass'] for t in period_cached)
for name,h in provenance['inherited_filesystem_boot_and_clip_units']['files'].items():assert sha(r/'sim'/name)==h,name
for name in ['clip_control','clip_control_collision','clip_voice','clip_pipeline','voice_restart_fixed']:
 log=(r/f'sim/{name}.log').read_text(errors='replace');assert 'TB_PASS' in log and '** Fatal:' not in log,name
 # The active test outputs must be newer than their changed sources.
 assert (r/f'sim/{name}.log').stat().st_mtime>max((r/p).stat().st_mtime for p in scope['changed_rtl'] if p.startswith('rtl/video_clip/')),name
release=w/'release/p47_clip_loop_sram_20261028';assert not release.exists()
release.mkdir()
for folder in ['source','reports','verification','tf_add']:(release/folder).mkdir()
bit=release/'campus_p47_clip_loop_SRAM_ONLY.bit';shutil.copy2(build/'campus_copy.bit',bit)
assert 100000<bit.stat().st_size<2097152,'Unexpected bitstream size'
for folder in ['rtl','constraints','assets']:shutil.copytree(r/folder,release/'source'/folder)
(release/'source/scripts').mkdir()
for name in ['build_layout.tcl','run_build.py','make_clip_assets.py','verify_loop_scope.py','publish_loop.py']:shutil.copy2(r/'scripts'/name,release/'source/scripts'/name)
if out.get('physical_strategy'):
 for name in ['ultra_layout.tcl','run_ultra_layout.py','td_timing_ultra.json']:shutil.copy2(r/'scripts'/name,release/'source/scripts'/name)
elif out.get('parent_gate_tag'):
 for name in ['retry_loop_layout.tcl','run_loop_layout.py']:shutil.copy2(r/'scripts'/name,release/'source/scripts'/name)
(release/'source/sim').mkdir()
for p in (r/'sim').iterdir():
 if p.is_file() and p.suffix in ['.sv','.v','.vh','.py','.do']:shutil.copy2(p,release/'source/sim'/p.name)
for name in ['period_cached_results.json','period_cached0.log','period_cached1.log','period_cached2.log','period_cached3.log','clip_unit_results.json','clip_pipeline_results.json','voice_restart_results.json','bmp_metadata_results.json','bmp_metadata.log','p44_regressions.json','file_cursor_equivalence_results.json','file_cursor_equivalence.log','clip_boot_results.json','clip_boot.log','clip_control.log','clip_control_collision.log','clip_scaler.log','clip_voice.log','clip_preload.log','clip_pipeline.log','voice_restart_fixed.log']:
 shutil.copy2(r/'sim'/name,release/'verification'/name)
for name in ['route.timing','route.area','route.qor']:shutil.copy2(build/name,release/'reports'/name)
for name in [f'build_{tag}.log',f'build_{tag}.json',f'build_{tag}_source.json','SCOPE_P47.json']:shutil.copy2(r/name,release/'verification'/name)
if out.get('parent_gate_tag'):
 parent=out['parent_gate_tag']
 for suffix in ['log','json','_source.json']:
  name=f'build_{parent}'+(suffix if suffix.startswith('_') else '.'+suffix)
  shutil.copy2(r/name,release/'verification'/name)
shutil.copy2(r/'assets/CLIP.BIN',release/'tf_add/CLIP.BIN')
verification={'created':datetime.datetime.now().isoformat(),'base':'P45 full feature release','build':out,
 'bit_sha256':sha(bit),'bit_bytes':bit.stat().st_size,'setup_wns_ns':sw,'setup_tns_ns':st,'hold_wns_ns':hw,'hold_tns_ns':ht,
 'resources':resources,'scope':scope,'tests':{'units':units,'pipeline':pipeline,'voice_restart_all_tick_phases':voice_restart,'file_cursor_equivalence':file_cursor,'bmp_metadata':metadata,'parser_regressions':parser_regressions,'period_cached':period_cached,'full_boot':boot},'test_provenance':provenance,
 'hardware_tested':False,'flash_modified':False,'actual_tf_card_modified':False,
 'behavior':['SW1 high loops until debounced low','No active-video gap between loops','Voice restarts every video loop',
 'Emergency takes priority; held SW1 resumes from clip start after release','Full P45 UI, clocks and media retained'],
 'limits':['Existing horizontal-line issue deferred by user, no fix claimed','Board acceptance pending',
 'Integration uses three actual clip frames and accelerated dwell; unit control covers twenty-frame cycles',
 'Loop duration is nominal two seconds plus at most one video refresh for boundary commit']}
(release/'verification.json').write_text(json.dumps(verification,ensure_ascii=False,indent=2),encoding='utf-8')
rebuild_note=''
if out.get('map_strategy',1)!=1 or out.get('pack_effort','high')!='high':
 rebuild_note=f"重建前设置 PowerShell 环境变量 $env:COPY_MAP_STRATEGY='{out.get('map_strategy',1)}' 和 $env:COPY_PACK_EFFORT='{out.get('pack_effort','high')}'。"
if out.get('physical_strategy'):
 rebuild_note="复现本次物理优化流程时，先执行 python scripts/run_build.py loop10 23 area_prior 生成综合网表（负时序会拒绝生成位流），再执行 python scripts/run_ultra_layout.py；TD 官方 TimingUltra 参数随源码保存。"
elif out.get('parent_gate_tag'):
 rebuild_note=f"复现复用综合网表的流程时，先执行 python scripts/run_build.py {out['parent_gate_tag']} 23 area_prior（该轮保留网表，负时序会拒绝生成位流），再执行 python scripts/run_loop_layout.py {out['seed']}。"
guide=f'''# 校安视界：SW1 短片循环播放完整版（SRAM）

## 使用
1. 保留 TF 卡根目录原有 CLIP.BIN 及全部图片、音频。素材未变化，无需重新复制。
2. BitWriter 选择 PROGRAM_SRAM，下载 campus_p47_clip_loop_SRAM_ONLY.bit。
3. 等待加载完毕，把 SW1 拨到开启位置：人物短片及“同学们，注意安全”语音循环播放。
4. SW1 拨回关闭位置：经原有开关消抖后，在下一画面帧边界停止，恢复宣教图片和原背景音。
5. 应急优先。应急解除后，若 SW1 仍开启，短片会从头开始循环；若关闭，则恢复正常宣教。

## 本次改动
基于原 P45 完整版，不是临时 50 MHz 简化版。保留字幕、波形、时间、参数、轮播、缩略图及原转场等功能。
调整短片开关控制及语音重播信号。循环之间 active 不拉低，避免每轮切回宣教图；同步语音 RAM 预热一个时钟，防止重播首采样沿用末尾数据。为收敛构建时序，上层 FAT 文件控制在有效文件簇切换时增加一个内部时钟周期，读取地址、字节序列和错误判定保持一致。
轮播周期终值提前寄存，避免在计数关键路径重复计算减一，轮播间隔与控制时刻不变。
BMP 元数据改在已有等待阶段校验：有效文件的扇区请求地址与时刻保持一致，无效簇号或文件尺寸保留原错误码，晚四个内部时钟报告。
控制域仍为 100 MHz，SDRAM/HDMI 时钟、约束、素材、SD 协议、加密控制器、FIFO 和 PHY 均未改动。
加载校验、运行期图像 CRC（C2）及原诊断显示均保留。
用户已暂缓横线排查，本版不声称消除已有偶发横线。

## 已完成验证
三轮二十帧控制序列、起止帧边界、消抖、就绪等待、应急抢占和恢复；两轮完整语音共 192000 个输出采样及背压；七轮不同采样相位重启；实际素材全尺寸逐像素集成检查，含两轮循环、拨回退出、重入及应急恢复。
集成仿真采用前三帧和加速帧停留；独立控制仿真覆盖完整二十帧。原素材、受保护模块及旧版备份经 SHA-256 复核。
文件控制已与原 P45 做 12 类、9532 字节事务等价比较；完整启动回归检查真实短片、碎片 FAT32、精确图像写入和两路背景音恢复。文件控制、短片单元和启动测试继承自相同相关 RTL 的已验证独立副本，来源及结果哈希见 verification.json；本副本重新运行轮播控制逐周期对照及完整画面仿真，不把继承结果写成重新运行。
BMP 元数据比较覆盖 24 类场景，另完成八项解析、超时与加载回归。轮播控制缓存周期终值，在四种配置下与原版对照 201404 个时钟周期，输出、轮播计数、按键、配置、忙状态和应急行为一致。
Setup WNS {sw:.3f} ns，Hold WNS {hw:.3f} ns，TNS 均为零。
位流 SHA-256：{sha(bit)}。
代码仿真和静态时序通过，实际画面与声音仍需上板确认。

## 建议上板检查
开启 SW1 连播至少三轮，检查每轮语音从头播放、循环间无宣教图闪回；中途关闭，检查恢复图片和背景音；再次开启可重播。再测试一次应急抢占与解除。

## 保留与返回
原 P45 发布包及 P44 Flash 备份均保持不变。本次未写 Flash，也未改实际 TF 卡。
完全断开全部供电再上电，可回到原 Flash 程序；K4 只复位当前 SRAM 程序，不更换位流。
重建可在 source 中执行 python scripts/run_build.py rebuild01 {out['seed']} {mode}，需本机 TD 安装路径；仿真需 ModelSim。{rebuild_note}每次使用独立输出目录，不覆盖旧结果。
'''
(release/'先读说明.md').write_text(guide,encoding='utf-8')
manifest={p.relative_to(release).as_posix():{'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(release.rglob('*')) if p.is_file()}
(release/'MANIFEST_SHA256.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
archive=release.with_suffix('.zip');assert not archive.exists()
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in sorted(release.rglob('*')):
  if p.is_file():z.write(p,p.relative_to(release.parent))
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
print(json.dumps({'release':str(release),'zip':str(archive),'bit_sha256':sha(bit),'setup_wns':sw,'hold_wns':hw,'resources':resources},ensure_ascii=False))
