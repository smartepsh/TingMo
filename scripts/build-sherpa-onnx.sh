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

mkdir -p "$DEPS"

# Upstream's build-swift-macos.sh builds everything sherpa-onnx can do — TTS,
# speaker diarization, keyword spotting — for both architectures. TingMo uses
# one path: offline CTC ASR on Apple Silicon. This is that script with the
# unused subsystems switched off, kept here rather than patched into .deps/ so
# a re-clone cannot silently revert it.
build_xcframework() {
  local src="$DEPS/sherpa-onnx"
  local build="$src/build-swift-macos"

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

if [ ! -d "$DEPS/sherpa-onnx/build-swift-macos/sherpa-onnx.xcframework" ]; then
  if [ ! -d "$DEPS/sherpa-onnx" ]; then
    echo "==> Cloning sherpa-onnx"
    git clone --depth 1 https://github.com/k2-fsa/sherpa-onnx.git "$DEPS/sherpa-onnx"
  fi
  echo "==> Building xcframework (this takes a while)"
  build_xcframework
else
  echo "==> xcframework already built, skipping"
fi

# The Swift wrapper is a plain source file rather than part of the framework, so
# refresh our vendored copy whenever the upstream checkout changes.
cp "$DEPS/sherpa-onnx/swift-api-examples/SherpaOnnx.swift" \
   "$REPO_ROOT/TingMo/SpeechEngine/Vendor/SherpaOnnx.swift"

echo
echo "Done. Build the app, then download the SenseVoice model from Settings."
