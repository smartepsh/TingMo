#!/usr/bin/env bash
#
# Fetches the upstream reference clips decoded by the sherpa-onnx engine tests.
#
# These are test fixtures only — they are read from .deps/ at test time via
# #filePath and never enter the app bundle or the DMG. Without them the decode
# tests skip rather than fail, so this is optional unless you want to verify the
# engines locally.
#
# Clips are pulled file-by-file from Hugging Face rather than downloading model
# archives. The app remains responsible for downloading the actual models.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS="$REPO_ROOT/.deps"

# Must match the engine descriptors and the folder names the tests look for.
SENSEVOICE_REPO="csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
SENSEVOICE_FIXTURES="$DEPS/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17/test_wavs"
PARAFORMER_REPO="csukuangfj/sherpa-onnx-paraformer-zh-2024-03-09"
PARAFORMER_FIXTURES="$DEPS/sherpa-onnx-paraformer-zh-2024-03-09/test_wavs"

# Honour the same mirror the app uses, so a China-based checkout can set
# HF_ENDPOINT=https://hf-mirror.com and have this work too.
HOST="${HF_ENDPOINT:-https://huggingface.co}"
HOST="${HOST%/}"

mkdir -p "$SENSEVOICE_FIXTURES" "$PARAFORMER_FIXTURES"

for clip in zh en ja ko yue; do
  target="$SENSEVOICE_FIXTURES/$clip.wav"
  if [ -f "$target" ]; then
    echo "==> SenseVoice $clip.wav already present, skipping"
    continue
  fi
  echo "==> Downloading SenseVoice $clip.wav"
  curl -fsSL -o "$target" "$HOST/$SENSEVOICE_REPO/resolve/main/test_wavs/$clip.wav?download=true"
done

# 0.wav is Mandarin; 2-zh-en.wav intentionally switches between Chinese and
# English and protects Paraformer's advertised mixed-language behavior.
for clip in 0 2-zh-en; do
  target="$PARAFORMER_FIXTURES/$clip.wav"
  if [ -f "$target" ]; then
    echo "==> Paraformer $clip.wav already present, skipping"
    continue
  fi
  echo "==> Downloading Paraformer $clip.wav"
  curl -fsSL -o "$target" "$HOST/$PARAFORMER_REPO/resolve/main/test_wavs/$clip.wav?download=true"
done

echo
echo "Done. Reference clips are in:"
echo "  $SENSEVOICE_FIXTURES"
echo "  $PARAFORMER_FIXTURES"
