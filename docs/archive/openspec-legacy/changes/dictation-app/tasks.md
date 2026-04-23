## 1. Project Setup

- [x] 1.1 Create Swift Package / Xcode project structure with macOS 13.0+ target, configure as LSUIElement (no Dock icon)
- [x] 1.2 Set up Info.plist with required privacy descriptions (microphone, speech recognition, accessibility, screen recording)
- [x] 1.3 Create the main App entry point with SwiftUI lifecycle and MenuBarExtra
- [x] 1.4 Set up GPL v3 license and README

## 2. Audio Device Management

- [x] 2.1 Implement audio input device enumeration via CoreAudio
- [x] 2.2 Implement device UID persistence (store UID + display name for historical devices)
- [x] 2.3 Implement device priority list ordering with drag-to-reorder (local per machine, not synced)
- [x] 2.4 Implement device online/offline status monitoring via CoreAudio property listeners
- [x] 2.5 Implement device disconnection handling during recording (stop recording, notify user, send captured audio to transcription)
- [x] 2.6 Build device management UI (list with online/offline indicators, reorder, remove historical devices)

## 3. Config Preset

- [ ] 3.1 Define Config Preset data model (engine, language, LLM params, device selection mode, active dictionaries)
- [ ] 3.2 Implement three device selection modes: follow system / specified device / priority list (referencing local audio-device module)
- [ ] 3.3 Implement preset CRUD (create, edit, duplicate, delete)
- [ ] 3.4 Implement preset switching from menu bar
- [ ] 3.5 Implement preset count limits (1 for basic, multiple for paid)
- [ ] 3.6 Implement iCloud sync for presets — sync all fields except API Keys; API Keys stored in local Keychain per device
- [ ] 3.7 (Future) Implement Config Preset import/export as shareable files (excluding API Keys)
- [ ] 3.8 (Future) Implement App-based preset auto-switching

## 4. Dictionary

- [ ] 4.1 Define dictionary data model (name, entries with correct term + optional misrecognition patterns)
- [ ] 4.2 Implement dictionary CRUD (create, edit, delete dictionaries and entries)
- [ ] 4.3 Implement dictionary selection in Config Preset (pick active dictionaries per preset)
- [ ] 4.4 Implement LLM prompt injection — inject active dictionary terms into LLM correction prompt context
- [ ] 4.5 Implement text replacement fallback — match misrecognition patterns and replace with correct terms when LLM is disabled
- [ ] 4.6 Implement iCloud sync for dictionaries (App Store version)
- [ ] 4.7 Build dictionary management UI

## 5. Speech Engine Architecture

- [x] 5.1 Define unified SpeechEngine protocol (start, stop, streaming support flag, language support, etc.)
- [x] 5.2 Implement engine registry / model list manager (browse, download, switch engines)
- [x] 5.3 Implement audio capture service (shared across all engines, using device selected by Config Preset via audio-device module)
- [x] 5.4 Implement audio format adaptation layer (convert capture format to engine-required format, e.g., 16kHz mono for WhisperKit)
- [ ] 5.5 Integrate WhisperKit as local engine (model download, Core ML acceleration, streaming support) — structural shell done, needs SPM dep + real transcription
- [ ] 5.6 Implement custom model download source configuration (WhisperKit `downloadBase` parameter) — config storage done, needs download implementation
- [ ] 5.7 Implement local model import — file picker / drag-and-drop, validate `.mlmodelc` files, copy to `~/Library/Application Support/TingMo/Models/` — validation/copy done, needs UI
- [x] 5.8 Integrate Apple Speech Framework as local engine (zero-download, real-time streaming)
- [ ] 5.9 Integrate Parakeet model support via CoreML (English-only, marked in model list) — placeholder only, awaiting Argmax SDK
- [x] 5.10 Implement remote engine adapter (Groq, ElevenLabs — record audio file, send to API, return result)
- [x] 5.11 Implement network failure handling for remote engines (retain audio file, notify user, allow retry)
- [x] 5.12 Add multi-language support with engine-language compatibility checking

## 6. Permission Handling

- [x] 6.1 Create PermissionManager to check and request microphone, speech recognition, accessibility, and screen recording permissions
- [x] 6.2 Implement permission status UI that guides user to System Settings when permissions are denied

## 7. Global Hotkey & External Invocation

- [x] 7.1 Implement global hotkey listener using CGEvent tap (default: Option+D)
- [x] 7.2 Implement dual-mode hotkey: key-down starts recording immediately; short press (< 300ms) = toggle mode, long press (≥ 300ms release) = press-to-record mode
- [x] 7.3 Implement cancel recording via ESC (default) during toggle mode — discard audio, return to idle; ESC only intercepted globally while recording is active
- [x] 7.4 Add custom hotkey configuration with persistence via UserDefaults
- [x] 7.5 Implement application exclusion list (ignore hotkey in specified apps, pass event through)
- [x] 7.6 Implement CLI interface (tingmo start / stop / toggle)
- [x] 7.7 Implement AppleScript support for dictation actions

## 8. Context Awareness

- [ ] 8.1 Implement selected text capture via Accessibility API
- [ ] 8.2 Implement active input field content capture via Accessibility API
- [ ] 8.3 Implement active window title and application name capture
- [ ] 8.4 Implement clipboard text content capture
- [ ] 8.5 Implement Active App full-text deep read via Accessibility API (with 1-2 second timeout)
- [ ] 8.6 Implement screenshot capture as fallback context (requires screen recording permission)
- [ ] 8.7 Build context aggregator with priority strategy (Accessibility-first + screenshot fallback)
- [ ] 8.8 Add context source configuration UI (toggles for each source, fallback strategy)
- [ ] 8.9 Implement password field detection and exclusion

## 9. LLM Correction

- [ ] 9.1 Define LLMProvider protocol for correction post-processing
- [ ] 9.2 Implement OpenAI compatible API adapter (chat completions format)
- [ ] 9.3 Implement Anthropic API adapter (messages format)
- [ ] 9.4 Build correction pipeline: receive transcription + context + active dictionary terms → send to LLM → return corrected text
- [ ] 9.5 Implement user-configurable parameters (endpoint, API Key, model, system prompt, temperature)
- [ ] 9.6 Secure API Key storage (Keychain)

## 10. Text Injection

- [ ] 10.1 Implement clipboard save/restore mechanism (preserving all pasteboard types)
- [ ] 10.2 Implement text injection via clipboard write + CGEvent Cmd+V simulation
- [ ] 10.3 Implement user-configurable clipboard restore delay (default: 500ms)

## 11. History

- [ ] 11.1 Define history entry data model (timestamp, final output text, raw transcription, engine, device, preset name, active app, duration)
- [ ] 11.2 Implement history storage (local database)
- [ ] 11.3 Build history list UI — chronological list, primarily showing final output text, with quick copy action
- [ ] 11.4 Implement audio file retention with configurable limit (default: last 3 sessions)
- [ ] 11.5 Implement retry from history — re-transcribe retained audio with current or different engine
- [ ] 11.6 Implement storage management UI (show storage usage for models, audio files, history database; clear/delete actions)
- [ ] 11.7 (Optional) Implement iCloud sync for history text entries (audio files not synced)

## 12. Status Indicator UI

- [x] 12.1 Implement Notch mode — embed waveform animation in camera notch area, with optional preview text
- [x] 12.2 Implement top-center mode — waveform animation at top center of active screen (fallback for no-notch devices)
- [x] 12.3 Implement floating window mode — waveform animation + transcription preview text
- [x] 12.4 Implement waveform animation that responds to audio input levels
- [x] 12.5 Implement processing/waiting indicator for non-streaming engines
- [x] 12.6 Add display mode selection in settings with auto-fallback (Notch → top-center on no-notch devices)
- [x] 12.7 Multi-monitor support — status indicator follows the display with the currently focused window

## 13. Onboarding & Localization

- [x] 13.1 Implement first-launch onboarding wizard (microphone → Accessibility → screen recording → engine download → hotkey setup)
- [x] 13.2 Allow skipping onboarding, with access to same steps from settings
- [x] 13.3 Implement multi-language UI support (Chinese Simplified + English), following macOS system language

## 14. Menu Bar UI

- [ ] 14.1 Create MenuBarExtra with microphone icon showing idle/active states
- [ ] 14.2 Build dropdown menu with status, Config Preset switcher, active audio device display, history access, settings, and quit
- [ ] 14.3 Create settings window with all configuration sections (Config Preset, audio device, dictionary, engine/model, hotkey, exclusion list, LLM, context, display mode, clipboard restore delay, audio retention, storage management, launch at login)

## 15. Integration & Polish

- [ ] 15.1 Wire full pipeline: hotkey/CLI/AppleScript → Config Preset resolution → device selection → audio capture → format adaptation → engine transcription → dictionary correction (text replacement if LLM off) → optional LLM correction (with context + dictionary terms) → history entry → clipboard → auto-paste
- [ ] 15.2 Implement error display through status indicator UI (not system notifications)
- [ ] 15.3 Add launch-at-login support using SMAppService (macOS 13+)
- [ ] 15.4 Integrate Sparkle for auto-update — appcast.xml on GitHub, update packages on GitHub Releases, prompt user to download (independent distribution only)
- [ ] 15.5 Code signing + notarization configuration
- [ ] 15.6 Test end-to-end flow and handle edge cases (no mic, device disconnected, permission denied, empty transcription, LLM timeout, engine not downloaded, network failure with retry)
