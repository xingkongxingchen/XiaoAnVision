from pathlib import Path
import binascii,struct
r=Path(__file__).resolve().parent
payload=b''.join(struct.pack('<I',((i*13)&255)|(((i//8)&255)<<8)|(((i^73)&255)<<16)) for i in range(256))
h=bytearray(512)
struct.pack_into('<4sHHHHIIH',h,0,b'XAV1',160,120,2,10,4,len(payload),binascii.crc_hqx(payload,0xffff))
(r/'clip_fixture.hex').write_text(''.join(f'{b:02x}\n' for b in h+payload),encoding='ascii')
