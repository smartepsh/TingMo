#!/usr/bin/env bash
#
# Fetches the reference clips SenseVoiceEngineTests decodes.
#
# These are test fixtures only — they are read from .deps/ at test time via
# #filePath and never enter the app bundle or the DMG. Without them the decode
# tests skip rather than fail, so this is optional unless you want to verify the
# engine locally.
#
# Pulled file-by-file from HuggingFace (~950 KB total) rather than from the
# GitHub release tarball, which bundles the same clips with a 158 MB model we do
# not need here — the app downloads the model itself.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS="$REPO_ROOT/.deps"

# Must match SenseVoiceEngine.repoID, and the folder name the tests look for.
REPO="csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
FIXTURES="$DEPS/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17/test_wavs"

# Honour the same mirror the app uses, so a China-based checkout can set
# HF_ENDPOINT=https://hf-mirror.com and have this work too.
HOST="${HF_ENDPOINT:-https://huggingface.co}"
HOST="${HOST%/}"

mkdir -p "$FIXTURES"

for clip in zh en ja ko yue; do
  target="$FIXTURES/$clip.wav"
  if [ -f "$target" ]; then
    echo "==> $clip.wav already present, skipping"
    continue
  fi
  echo "==> Downloading $clip.wav"
  curl -fsSL -o "$target" "$HOST/$REPO/resolve/main/test_wavs/$clip.wav"
done

echo
echo "Done. Reference clips are in $FIXTURES"
