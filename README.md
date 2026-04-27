# TingMo 听墨

A lightweight, always-available intelligent dictation app for macOS.

TingMo lives in your menu bar and provides pluggable speech-to-text with optional LLM-powered correction. Press a hotkey, speak, and the transcribed text is automatically pasted at your cursor.

## Features

- **Pluggable speech engines** — WhisperKit (on-device), Apple Speech Framework, remote APIs (Groq, ElevenLabs)
- **LLM correction** — Optional post-processing via OpenAI-compatible or Anthropic APIs
- **Context-aware** — Reads selected text, window info, and clipboard to improve correction accuracy
- **Config Presets** — Bundle engine, language, LLM, and device settings into switchable profiles
- **Custom dictionaries** — User-defined terminology for better recognition of domain-specific terms
- **Audio device management** — Choose, prioritize, and remember input devices
- **Global hotkey** — Short press to toggle, long press to record, ESC to cancel
- **Multiple status UIs** — Notch, top-center, or floating window display modes
- **CLI & AppleScript** — Automate with `tingmo start/stop/toggle` or Shortcuts

## Requirements

- macOS 13.0+ (Ventura)
- Apple Silicon or Intel

## Building

Open `TingMo/TingMo.xcodeproj` in Xcode and build.

For local development, run this once before granting macOS privacy permissions:

```bash
./scripts/setup-local-signing.sh
```

That generates an ignored `Config/LocalSigning.xcconfig` plus a local
`TingMo Local Development` signing keychain. Local builds then use a stable
certificate signature instead of a new ad-hoc cdhash on each build, so
Accessibility and other TCC permissions do not need to be deleted and granted
again after rebuilding.

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).
