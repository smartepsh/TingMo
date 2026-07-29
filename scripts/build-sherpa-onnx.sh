#!/usr/bin/env bash
#
# Builds the sherpa-onnx static xcframework that SenseVoiceEngine links against.
#
# sherpa-onnx is a C++ project with no SwiftPM support, so unlike WhisperKit it
# cannot be resolved by Xcode — the library has to exist before the app will
# link. Run this once after cloning; the artefacts land in .deps/ (git-ignored)
# and later builds reuse them.
#
# Nothing here ships to users: the static library is linked into the binary, and
# the SenseVoice model is downloaded by the app itself from Settings.
#
# For the reference clips the engine tests decode, see fetch-test-fixtures.sh.
#
# Takes roughly 10 minutes on an M-series Mac.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS="$REPO_ROOT/.deps"
SRC="$DEPS/sherpa-onnx"

# Pinned rather than tracking upstream's default branch. Two things here are
# downstream of the checkout — the static library the app links against, and the
# vendored SherpaOnnx.swift copied out at the end — so an unpinned clone makes
# both a moving target: the release workflow's "vendored sources unchanged"
# check starts failing on upstream commits nobody here reviewed. Upstream showed
# the sharp edge of that on 2026-07-29, when 9ad8c88 deleted
# swift-api-examples/SherpaOnnx.swift outright and the copy below simply had no
# source file left.
#
# To bump: change this revision, re-run the script, commit the refreshed
# TingMo/SpeechEngine/Vendor/SherpaOnnx.swift alongside it.
SHERPA_ONNX_REV="0a03d8546f8136073c210ec895109a0c64f90daa"

mkdir -p "$DEPS"

# Upstream's build-swift-macos.sh builds everything sherpa-onnx can do — TTS,
# speaker diarization, keyword spotting — for both architectures. TingMo uses
# one path: offline CTC ASR on Apple Silicon. This is that script with the
# unused subsystems switched off, kept here rather than patched into .deps/ so
# a re-clone cannot silently revert it.
build_xcframework() {
  local build="$SRC/build-swift-macos"

  mkdir -p "$build"
  (
    cd "$build"
    cmake \
      -DSHERPA_ONNX_ENABLE_BINARY=OFF \
      -DSHERPA_ONNX_BUILD_C_API_EXAMPLES=OFF \
      -DCMAKE_OSX_ARCHITECTURES="arm64" \
      -DCMAKE_INSTALL_PREFIX=./install \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      -DSHERPA_ONNX_ENABLE_PYTHON=OFF \
      -DSHERPA_ONNX_ENABLE_TESTS=OFF \
      -DSHERPA_ONNX_ENABLE_CHECK=OFF \
      -DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF \
      -DSHERPA_ONNX_ENABLE_JNI=OFF \
      -DSHERPA_ONNX_ENABLE_C_API=ON \
      -DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF \
      -DSHERPA_ONNX_ENABLE_TTS=OFF \
      -DSHERPA_ONNX_ENABLE_SPEAKER_DIARIZATION=OFF \
      ../

    make -j"$(sysctl -n hw.ncpu)"
    make install
    rm -f ./install/include/cargs.h

    # Merge whichever component libraries this configuration produced: turning
    # TTS off removes espeak-ng and piper_phonemize, so a fixed list would break.
    local libs=()
    for lib in \
      libsherpa-onnx-c-api.a \
      libsherpa-onnx-core.a \
      libkaldi-native-fbank-core.a \
      libkissfft-float.a \
      libsherpa-onnx-fstfar.a \
      libsherpa-onnx-fst.a \
      libsherpa-onnx-kaldifst-core.a \
      libkaldi-decoder-core.a \
      libucd.a \
      libpiper_phonemize.a \
      libespeak-ng.a \
      libssentencepiece_core.a
    do
      [ -f "./install/lib/$lib" ] && libs+=("./install/lib/$lib")
    done

    libtool -static -o ./install/lib/libsherpa-onnx.a "${libs[@]}"

    rm -rf sherpa-onnx.xcframework
    xcodebuild -create-xcframework \
      -library install/lib/libsherpa-onnx.a \
      -headers install/include \
      -output sherpa-onnx.xcframework
  )
}

# A plain `git clone --depth 1` cannot name a revision, and CI restores .deps
# from a cache that may hold a checkout of some earlier pin, so fetch the exact
# commit into whatever is already there. GitHub serves fetch-by-SHA, which keeps
# this a single-commit download rather than a full history.
if [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)" != "$SHERPA_ONNX_REV" ]; then
  echo "==> Fetching sherpa-onnx $SHERPA_ONNX_REV"
  mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" remote add origin https://github.com/k2-fsa/sherpa-onnx.git 2>/dev/null || true
  git -C "$SRC" fetch -q --depth 1 origin "$SHERPA_ONNX_REV"
  git -C "$SRC" checkout -q --force FETCH_HEAD
  # The C++ sources just moved under it, so anything built from the previous
  # revision is stale — including an xcframework restored from the CI cache.
  rm -rf "$SRC/build-swift-macos"
fi

if [ ! -d "$SRC/build-swift-macos/sherpa-onnx.xcframework" ]; then
  echo "==> Building xcframework (this takes a while)"
  build_xcframework
else
  echo "==> xcframework already built, skipping"
fi

# The Swift wrapper is a plain source file rather than part of the framework, so
# refresh our vendored copy whenever the pinned revision changes.
cp "$SRC/swift-api-examples/SherpaOnnx.swift" \
   "$REPO_ROOT/TingMo/SpeechEngine/Vendor/SherpaOnnx.swift"

echo
echo "Done. Build the app, then download the SenseVoice model from Settings."
