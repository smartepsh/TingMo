## ADDED Requirements

### Requirement: Config Preset data model
The system SHALL support Config Presets — named configuration bundles that combine multiple settings into a single switchable profile.

#### Scenario: Preset contents
- **WHEN** a Config Preset is created or edited
- **THEN** the preset SHALL contain the following configurable fields: speech recognition engine, language, LLM correction toggle and parameters (provider, endpoint, model, system prompt, temperature), audio device selection mode, and active dictionary selection (zero or more from the global dictionary list)

### Requirement: Audio device selection mode in preset
Each Config Preset SHALL include an audio device selection mode that determines how the input device is chosen when the preset is active. The mode is a strategy reference; actual device lists and priority ordering are managed locally per machine by the `audio-device` module.

#### Scenario: Follow system default
- **WHEN** a preset's device selection mode is set to "system"
- **THEN** the system SHALL use the macOS default audio input device when this preset is active

#### Scenario: Specified device
- **WHEN** a preset's device selection mode is set to "specified"
- **THEN** the system SHALL use the device currently selected (pinned) in the local audio device settings; if it is not online, the system SHALL notify the user that the device is unavailable

#### Scenario: Priority list
- **WHEN** a preset's device selection mode is set to "priority"
- **THEN** the system SHALL iterate through the local device priority list (managed by `audio-device` module) in order and use the first device that is currently online; if none are available, the system SHALL notify the user

### Requirement: Preset management
The system SHALL allow users to create, edit, duplicate, delete, and reorder Config Presets.

#### Scenario: Create preset
- **WHEN** the user creates a new Config Preset
- **THEN** the system SHALL create a preset with default values that the user can customize

#### Scenario: Edit preset
- **WHEN** the user edits an existing Config Preset
- **THEN** the system SHALL allow modifying any field within the preset

#### Scenario: Delete preset
- **WHEN** the user deletes a Config Preset
- **THEN** the system SHALL remove the preset; if it was the active preset, the system SHALL switch to the next available preset

### Requirement: Preset switching
The system SHALL allow users to quickly switch between Config Presets from the menu bar dropdown.

#### Scenario: Manual switch
- **WHEN** the user selects a different Config Preset from the menu bar
- **THEN** the system SHALL immediately apply the selected preset's full configuration (engine, language, LLM settings, device selection mode, active dictionaries)

### Requirement: Preset count limits
The system SHALL enforce preset count limits based on the application version.

#### Scenario: Basic version (self-compiled)
- **WHEN** the user is on the basic/self-compiled version
- **THEN** the system SHALL allow one Config Preset only

#### Scenario: Paid version (App Store)
- **WHEN** the user is on the paid/App Store version
- **THEN** the system SHALL allow creating and managing multiple Config Presets

### Requirement: iCloud sync for presets
The system SHALL sync Config Presets via iCloud for App Store version users, with a clear separation between synced and local-only data.

#### Scenario: Synced fields
- **WHEN** a Config Preset is synced via iCloud
- **THEN** the following fields SHALL be synced across devices: preset name, speech recognition engine preference, language, LLM provider, LLM endpoint URL, LLM model, system prompt, temperature, LLM correction toggle, and audio device selection mode (strategy only — "system" / "specified" / "priority")

#### Scenario: Local-only fields
- **WHEN** a Config Preset is synced via iCloud
- **THEN** the following fields SHALL NOT be synced and remain local to each device: API Keys (stored in local Keychain)

#### Scenario: New device receives synced preset
- **WHEN** a Config Preset is synced to a new device for the first time
- **THEN** the preset SHALL be usable immediately for all synced fields; the user will need to provide API Keys locally via Keychain

#### Scenario: iCloud sync unavailable
- **WHEN** the user is on the self-compiled version or not signed into iCloud
- **THEN** Config Presets SHALL be stored locally only

### Requirement: Config Preset import/export (future)
The system SHALL support exporting and importing Config Presets as files for sharing between users (planned for future implementation).

#### Scenario: Export preset
- **WHEN** the user exports a Config Preset
- **THEN** the system SHALL create a shareable file containing the preset configuration, excluding API Keys

#### Scenario: Import preset
- **WHEN** the user imports a Config Preset file
- **THEN** the system SHALL create a new preset from the file; the user will need to provide their own API Keys

### Requirement: Future — App-based preset auto-switching
The system SHALL support automatic Config Preset switching based on the currently active application (planned for future implementation).

#### Scenario: App binding configured
- **WHEN** the user has bound a Config Preset to a specific application, and that application becomes the active (frontmost) app
- **THEN** the system SHALL automatically switch to the bound Config Preset

#### Scenario: No app binding
- **WHEN** the active application has no bound Config Preset
- **THEN** the system SHALL remain on the currently selected (manual) preset
