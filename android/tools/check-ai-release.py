#!/usr/bin/env python3
"""Check release APK for AI debug hooks and bundled speech weights."""
import sys
import zipfile
from pathlib import Path

apk = Path(sys.argv[1])
with zipfile.ZipFile(apk) as archive:
    entries = archive.namelist()
    dex = b''.join(archive.read(name) for name in entries if name.endswith('.dex'))
    for forbidden in [b'AiFixtureActivity', b'FakeLocalGenerator', b'ai-debug', b'ReadingFixtureActivity', b'ShelvesFixtureActivity']:
        assert forbidden not in dex, f'Debug hook in release DEX: {forbidden.decode()}'
    for required in [b'NanoGenerator', b'WhisperTranscriber', b'MomentOutput_GeneratedProvider', b'HeadlineRecapOutput_GeneratedProvider']:
        assert required in dex, f'Missing production AI class: {required.decode()}'
    assert not any('ggml-base' in name or name.endswith(('.wav', '.aiff')) or (name.endswith('.bin') and name != 'DebugProbesKt.bin') for name in entries), 'Model or test audio bundled in APK'
    for abi in ['arm64-v8a', 'x86_64']:
        assert f'lib/{abi}/libunpaged_whisper.so' in entries, f'Missing native Whisper for {abi}'
print('Release APK: debug hooks absent; production AI/schema classes present; no weights or speech fixtures; both native ABIs present.')
