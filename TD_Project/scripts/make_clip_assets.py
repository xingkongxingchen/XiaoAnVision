"""Build the fixed 2-second / 10-fps campus reminder and FPGA clip payload."""
from pathlib import Path
import binascii, hashlib, json, struct, subprocess
from PIL import Image, ImageDraw, ImageFont

root=Path(__file__).resolve().parents[1]
assets=root/'assets'
frames=assets/'frames'
frames.mkdir(exist_ok=True)
source=Image.open(assets/'principal_sprite.png').convert('RGB')
w,h=source.size
font=ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc',14)
poses=[0,1,2,1,3,1,2,1,0,1,2,1,3,2,1,0,1,2,1,0]
caption='同学们，注意安全！'
payload=bytearray()
for i,pose in enumerate(poses):
    x,y=pose%2,pose//2
    box=(x*w//2+2,y*h//2+2,(x+1)*w//2-2,(y+1)*h//2-2)
    im=source.crop(box).resize((160,120),Image.Resampling.LANCZOS)
    draw=ImageDraw.Draw(im)
    draw.rectangle((0,98,159,119),fill='#fff6df')
    draw.text((80,99),caption,font=font,anchor='mt',fill='#9d1717')
    im.save(frames/f'frame_{i:02d}.png')
    for r,g,b in im.getdata():payload.extend((b,g,r,0))
subprocess.run(['ffmpeg','-y','-v','error','-i',str(assets/'principal_voice_source.wav'),
    '-af','atempo=1.28,apad,atrim=duration=2','-ar','8000','-ac','1',
    '-c:a','pcm_s8','-f','s8',str(assets/'clip_voice.s8')],check=True)
voice=(assets/'clip_voice.s8').read_bytes()
assert len(voice)==16000
crc=binascii.crc_hqx(payload+voice,0xffff)
header=bytearray(512)
struct.pack_into('<4sHHHHIIH',header,0,b'XAV1',160,120,20,10,4,len(payload),crc)
struct.pack_into('<HIBB',header,22,8000,len(voice),8,1)
(assets/'CLIP.BIN').write_bytes(header+payload+voice)
(assets/'clip_voice.hex').write_text(''.join(f'{v:02x}\n' for v in voice+bytes(16384-len(voice))),encoding='ascii')
subprocess.run(['ffmpeg','-y','-v','error','-framerate','10','-i',str(frames/'frame_%02d.png'),
    '-f','s8','-ar','8000','-ac','1','-i',str(assets/'clip_voice.s8'),
    '-vf','scale=640:480:flags=neighbor','-c:v','libx264','-pix_fmt','yuv420p',
    '-c:a','aac','-t','2',str(assets/'校长爷爷_注意安全_两秒预览.mp4')],check=True)
(assets/'ASSET_MANIFEST.json').write_text(json.dumps({
    'text':caption,'principal':'Original fictional character, generated with built-in imagegen',
    'voice':'Microsoft Kangkang local speech synthesis; 8000 Hz signed 8-bit mono, 2 seconds; boot preload to BRAM',
    'width':160,'height':120,'frames':20,'fps':10,'image_bytes':len(payload),'voice_bytes':len(voice),
    'media_crc16_ccitt_false':f'{crc:04x}','crc_scope':'image bytes then voice bytes',
    'clip_bytes':len(header+payload+voice),'clip_sha256':hashlib.sha256(header+payload+voice).hexdigest(),
    'frame_sha256':[hashlib.sha256(payload[i*76800:(i+1)*76800]).hexdigest() for i in range(20)]
},ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'clip_bytes':len(header+payload+voice),'crc16':f'{crc:04x}','voice_samples':len(voice)},ensure_ascii=False))
