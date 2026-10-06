#!/usr/bin/env python3
"""Generate real 8kHz PCM files for the system document picker; no app test hooks."""
import sys
import wave
from pathlib import Path

root = Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)
for name, seconds in [('Chapter 1.wav', 300), ('Chapter 2.wav', 300),
                      ('Chapter 10.wav', 60), ('Another.wav', 300), ('E2E Import.wav', 123)]:
    with wave.open(str(root / name), 'wb') as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(8000)
        audio.writeframes(bytes(seconds * 8000 * 2))
(root / 'Invalid.mp3').write_text('This is deliberately not audio.\n')
