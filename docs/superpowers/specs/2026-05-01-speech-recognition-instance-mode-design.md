# Speech Recognition Settings: Instance Mode Redesign

**Date:** 2026-05-01
**Status:** Draft
**Scope:** Speech Recognition settings page refactored to mirror Correction's instance-based model management

---

## Problem

The current Speech Recognition settings page has several issues:

1. **Inconsistent UX** — Correction page uses an instance-based model (LLMInstance), while Speech Recognition uses a flat engine list with inline API key configuration
2. **No multi-instance support** — Each remote provider (Groq, ElevenLabs) can only have one API key
3. **Mixed responsibilities** — The page both manages models AND selects the active engine (the latter should be in Presets)
4. **Input Language filter placement** — The language filter is on the management page but is conceptually a selection aid for Presets
5. **No Preset reference visibility** — Users can't see which Preset references which engine

## Goal

Refactor Speech Recognition settings to use an instance-based pattern consistent with Correction, where:

- **Speech Recognition page** = model/connection management only
- **Preset Settings page** = engine selection (with language filter as UI aid)
- Remote STT providers support multiple instances (different API keys)
- Preset reference indicators are visible on both pages

---

## Data Model

### New: `STTInstance`

Mirrors `LLMInstance` for remote speech-to-text providers.

```swift
struct STTInstance: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var displayName: String        // e.g. "Groq Whisper", "My Groq Key 2"
    var provider: STTProviderID
    var keychainService: String    // "tingmo.stt.instance.<UUID>"
}
```

### New: `STTProviderID`

```swift
enum STTProviderID: String, Codable, CaseIterable {
    case groq          // Groq Whisper
    case elevenlabs    // ElevenLabs Scribe
    // future: case parakeet, case deepgram, etc.

    var displayName: String
    var defaultModel: String
    var supportedLanguages: [String]
    var requiresAPIKey: Bool { true }
}
```

### New: `STTInstanceStore`

Mirrors `LLMInstanceStore`. Manages STT instances with persistence.

```swift
@Observable
final class STTInstanceStore {
    var instances: [STTInstance]

    // Persistence: UserDefaults JSON under "STTInstanceStore.instances"
    // API Keys: EncryptedKeyStore keyed by instance.keychainService

    func instance(id: UUID) -> STTInstance?
    func upsert(_ instance: STTInstance)
    func addInstance(provider: STTProviderID) -> STTInstance
    func deleteInstance(id: UUID) -> Bool
    func hasAPIKey(for instance: STTInstance) -> Bool
    func saveAPIKey(_ key: String, for instance: STTInstance) -> Bool
    func clearAPIKey(for instance: STTInstance) -> Bool
}
```

### ConfigPreset (no changes)

```swift
struct ConfigPreset {
    var speechEngineID: String   // unchanged; prefix determines lookup:
                                 // "whisperkit-*" → WhisperKit engine
                                 // "stt-instance-<UUID>" → STTInstance
    // ... other fields unchanged
}
```

### EngineRegistry Changes

- Remove static registration of `RemoteSpeechEngine` for groq/elevenlabs
- Add `resolveEngine(id:sttInstanceStore:)` method:
  - `"whisperkit-*"` → lookup in WhisperKit engines
  - `"stt-instance-<UUID>"` → lookup in STTInstanceStore, create RemoteSpeechEngine dynamically
- WhisperKit engines continue to be registered statically (they need download management)

---

## UI Design

### Speech Recognition Page

**Responsibility:** Model and connection management only. Does NOT control which engine is active.

```
┌─────────────────────────────────────────────────────────────┐
│  Speech Recognition                                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─ WhisperKit Models ─────────────────────────────────────┐│
│  │  Download Source: [HuggingFace ▾]                       ││
│  │                                                         ││
│  │  Tiny     75MB    ✓ Downloaded  [Used by: Default]      ││
│  │                        [Delete]                         ││
│  │  Base     150MB   ○ Not installed  [Download]           ││
│  │  Small    500MB   ○ Not installed  [Download]           ││
│  │  Medium   1.5GB   ○ Not installed  [Download]           ││
│  │  Large-v3 3.1GB   ○ Not installed  [Download]           ││
│  │                                                         ││
│  │  Total: 75MB / 5.5GB                                    ││
│  │                                                         ││
│  │  ── Imported Models ──                                  ││
│  │  [Drag & drop or Import Model Folder...]                ││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
│  ┌─ Remote STT Providers ──────────────────────────────────┐│
│  │  (+) Add Instance                                       ││
│  │                                                         ││
│  │  ▸ Groq Whisper                          [Active badge] ││
│  │    Provider: Groq                                       ││
│  │    API Key: [sk_...xYz]  [Save] [Test Connection]      ││
│  │    Preset refs: "Default"                               ││
│  │    [Delete Instance]                                    ││
│  │                                                         ││
│  │  ▸ ElevenLabs Scribe                                     ││
│  │    Provider: ElevenLabs                                 ││
│  │    API Key: [****]  [Save] [Test Connection]            ││
│  │    [Delete Instance]                                    ││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
│  ┌─ Coming Soon ───────────────────────────────────────────┐│
│  │  NVIDIA Parakeet (English-only, 600MB)                  ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

**Key behaviors:**
- WhisperKit section: same as current `ModelDownloadView` + `ImportedModelSection`, with added Preset reference indicators
- Remote section: mirrors `LLMInstanceSettingsSection` — each instance is a disclosure group with Provider, API Key, Test Connection
- Active badge: shows which Preset is currently using this engine
- Preset reference indicator: "Used by: Default" (helps users understand delete impact)
- Delete confirmation: warns if instance is referenced by a Preset
- **Add Instance flow:** Click "+" → provider picker popover (Groq, ElevenLabs) → new instance created with default name ("Groq Whisper", "ElevenLabs Scribe") → expand to configure API key
- **Delete Instance flow:** If referenced by Preset → confirmation dialog warning → delete instance + clear API key + clear Preset reference

### Preset Settings Page Changes

Add Speech Engine selector and Input Language filter to existing `PresetSettingsSection`.

```
┌─────────────────────────────────────────────────────────────┐
│  Preset Settings                                            │
├─────────────────────────────────────────────────────────────┤
│  Preset Name: [Default]                                     │
│                                                             │
│  ── Speech Recognition ──                                   │
│                                                             │
│  Filter by language: [English ✓] [中文 ✓] [日本语 ☐] ...    │
│  (UI filter only, not saved to preset)                      │
│                                                             │
│  Speech Engine: [▾ Tiny (WhisperKit)          ]             │
│                 ├─ WhisperKit Models                        │
│                 │  ✓ Tiny (WhisperKit)     75MB  Local      ││
│                 │    Base (WhisperKit)     150MB Local      ││
│                 │    Small (WhisperKit)    500MB Local      ││
│                 │    ...                                    ││
│                 ├─ Remote Providers                         ││
│                 │    Groq Whisper            Remote         ││
│                 │    ElevenLabs Scribe       Remote         ││
│                 └─ (none)                                   ││
│                                                             │
│  ── Output ──                                               │
│  Output Language: [Raw (no translation) ▾]                  │
│                                                             │
│  ── Correction ──                                           │
│  Enable LLM Correction: [toggle]                            │
│  Correction Engine: [▾ None | OpenAI | Anthropic | ...]     │
│  System Prompt: [...]                                       │
│  Temperature: [0.3]                                         │
└─────────────────────────────────────────────────────────────┘
```

**Key behaviors:**
- Input Language filter: multi-select chips/toggles, UI-only (not persisted)
- Engine picker: grouped list showing WhisperKit models and Remote instances
- Incompatible engines (filtered out by language) shown grayed out or hidden
- Selecting an engine sets `preset.speechEngineID` and updates `EngineRegistry.activeEngineID`
- Unready engines (not downloaded / no API key) shown with status indicator and disabled
- Default selection: "None" option available (no engine configured)

---

## File Changes

### New Files

| File | Purpose |
|---|---|
| `TingMo/SpeechEngine/STTInstance.swift` | STTInstance struct |
| `TingMo/SpeechEngine/STTProviderID.swift` | STTProviderID enum |
| `TingMo/SpeechEngine/STTInstanceStore.swift` | Instance management store |
| `TingMo/SpeechEngine/STTInstanceSettingsSection.swift` | Remote STT instance UI |

### Modified Files

| File | Changes |
|---|---|
| `EngineRegistry.swift` | Dynamic engine resolution via `resolveEngine(id:sttInstanceStore:)` |
| `RemoteSpeechEngine.swift` | Accept `STTInstance` config instead of hardcoded `RemoteEngineConfig` |
| `SettingsView.swift` | Speech page uses new components; Preset page adds Speech Engine picker |
| `PresetSettingsSection.swift` | Add Speech Engine selector + language filter |
| `EngineSettingsView.swift` | Remove or simplify (no more Use button, engine list) |
| `RemoteEngineSection.swift` | Delete (replaced by STTInstanceSettingsSection) |

### Unchanged Files

| File | Reason |
|---|---|
| `WhisperKitEngine.swift` | No changes needed |
| `ModelDownloadView.swift` | Add Preset reference indicator only |
| `ImportedModelSection.swift` | No changes needed |
| `EncryptedKeyStore.swift` | No changes needed |
| `ConfigPreset.swift` | `speechEngineID` format unchanged |

---

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Input Language storage | UI-only, not in Preset | User clarified: it's a filter aid, not a config value |
| `speechEngineID` type | Keep as String | Prefix convention (`whisperkit-*` / `stt-instance-*`) avoids type change |
| WhisperKit vs Remote | Separate UI sections | Different management paradigms (download vs API key) |
| STTInstance vs LLMInstance | Separate types | Different provider ecosystems, different validation rules |
| No migration | New app | No backward compatibility needed |
