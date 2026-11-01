from pathlib import Path
import subprocess,os,json
r=Path(__file__).resolve().parent
s=(r.parent/'rtl/filesystem/fat32_bmp_read.v').read_text()
s=s.replace('module fat32_bmp_read #(','module p37_finish_mutant #(',1)
s=s.replace(' reg finish_bad_count;',' reg finish_bad_count;\n reg stale_bad_count;\n always @(posedge clk or posedge rst)begin\n  if(rst)stale_bad_count<=0;else stale_bad_count<=finish_bad_count;\n end',1)
s=s.replace('if(finish_bad_count)begin error_code<=3;state<=FAIL;end','if(stale_bad_count)begin error_code<=3;state<=FAIL;end',1)
(r/'p37_finish_mutant.v').write_text(s)
t=(r/'tb_parser_finish.sv').read_text().replace('module tb_parser_finish #(','module tb_parser_finish_mutant #(',1).replace(' fat32_bmp_read #(',' p37_finish_mutant #(',1)
(r/'tb_parser_finish_mutant.sv').write_text(t)
do='''transcript on
onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
vlib work_finish_negative
vlog -sv -work work_finish_negative {*}[glob ../rtl/filesystem/*.v] p36_parser_reference.v p37_finish_mutant.v tb_parser_finish_mutant.sv
vsim -c work_finish_negative.tb_parser_finish_mutant -gSCALE=1
run -all
quit -code 0 -f
'''
(r/'run_finish_negative.do').write_text(do)
p=subprocess.run(['G:/quartus/modelsim_ase/win32aloem/vsim.exe','-c','-do','run_finish_negative.do','-l','p37_finish_negative.log'],cwd=r,capture_output=True,text=True,timeout=60)
log=(r/'p37_finish_negative.log').read_text(errors='replace')
expected='** Fatal: End contract case=7 SCALE=1 code=3/0' in log
assert expected,log[-2200:]
out={'expected_failure_detected':True,'mutation':'One-cycle stale completion verdict, test-only source','failure_case':7,'production_source_changed':False}
(r/'p37_finish_negative.json').write_text(json.dumps(out,indent=2));print(json.dumps(out))
