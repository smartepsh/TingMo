// Exposes the sherpa-onnx C API to Swift, which SherpaOnnx.swift wraps.
//
// The library is built on demand and is not committed — run
// scripts/build-sherpa-onnx.sh before building the app. See Config/Signing.xcconfig
// for the search paths and linker flags.

#import "sherpa-onnx/c-api/c-api.h"
