#!/usr/bin/env python3
"""Generate real 8kHz PCM files for the system document picker; no app test hooks."""
import sys
import subprocess
import struct
import zlib
import shutil
import wave
from pathlib import Path

root = Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)
for name, seconds in [('Chapter 1.wav', 300), ('Chapter 2.wav', 300),
                      ('E2E Chapter 1.wav', 300), ('E2E Chapter 2.wav', 300),
                      ('Chapter 10.wav', 60), ('Another.wav', 300), ('E2E Import.wav', 123)]:
    with wave.open(str(root / name), 'wb') as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(8000)
        audio.writeframes(bytes(seconds * 8000 * 2))
(root / 'Invalid.mp3').write_text('This is deliberately not audio.\n')

# Real AAC in an M4B, with both QuickTime text chapters and a Nero chpl atom.
metadata = root / 'chapters.ffmetadata'
metadata.write_text(';FFMETADATA1\n' + ''.join(
    f'[CHAPTER]\nTIMEBASE=1/1000\nSTART={i*30000}\nEND={(i+1)*30000}\ntitle={title}\n'
    for i, title in enumerate(['Opening', 'The Journey', 'Home Again'])))
subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
    '-f', 'lavfi', '-i', 'anullsrc=r=22050:cl=mono', '-i', str(metadata),
    '-t', '90', '-map_metadata', '1', '-map_chapters', '1', '-c:a', 'aac',
    '-b:a', '32k', '-f', 'mp4', str(root / 'Embedded Chapters.m4b')], check=True)
metadata.unlink()
path = root / 'Embedded Chapters.m4b'
data = path.read_bytes()
payload = bytes([1, 0, 0, 0]) + bytes(4) + bytes([3])
for index, title in enumerate(['Opening', 'The Journey', 'Home Again']):
    text = title.encode()
    payload += struct.pack('>Q', index * 300_000_000) + bytes([len(text)]) + text
chpl = struct.pack('>I4s', len(payload) + 8, b'chpl') + payload
udta = struct.pack('>I4s', len(chpl) + 8, b'udta') + chpl
offset = 0
while offset < len(data):
    size, kind = struct.unpack_from('>I4s', data, offset)
    if kind == b'moov':
        data = data[:offset] + struct.pack('>I4s', size + len(udta), b'moov') + data[offset+8:offset+size] + udta + data[offset+size:]
        break
    offset += size
path.write_bytes(data)

def png_chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))
pixels = b''.join(b'\0' + b''.join(bytes([x % 256, y % 256, 100]) for x in range(400)) for y in range(200))
(root / 'Cover.png').write_bytes(b'\x89PNG\r\n\x1a\n' +
    png_chunk(b'IHDR', struct.pack('>IIBBBBB', 400, 200, 8, 2, 0, 0, 0)) +
    png_chunk(b'IDAT', zlib.compress(pixels)) + png_chunk(b'IEND', b''))
# Speech synthesized locally by macOS say, original text authored for Unpaged E2E.
# No third-party recording or book excerpt. Used only by the test document picker.
speech = root / 'Speech.aiff'
subprocess.run(['say', '-v', 'Samantha', '-r', '155', '-o', str(speech),
    'The old garden was quiet in the morning. Alice opened the gate and listened to the birds. A new journey was about to begin.'], check=True)
subprocess.run(['afconvert', str(speech), str(root / 'AI Speech.wav'), '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1'], check=True)
speech.unlink()
with wave.open(str(root / 'AI Speech.wav')) as spoken:
    has_speech = spoken.getnframes() > spoken.getframerate() * 2
if not has_speech:
    # macOS speech synthesis may exit 0 with no frames inside a process sandbox.
    shutil.copyfile(Path(__file__).parent / 'fixtures/jfk.wav', root / 'AI Speech.wav')
with wave.open(str(root / 'AI Speech.wav')) as spoken:
    assert spoken.getnchannels() == 1 and spoken.getsampwidth() == 2 and spoken.getframerate() == 16000
    assert spoken.getnframes() > 32000, 'Speech fixture must contain actual audio'
