## ADDED Requirements

### Requirement: User-defined dictionaries
The system SHALL support user-defined dictionaries (terminology lists) that improve transcription accuracy by providing domain-specific terms, proper nouns, abbreviations, and other custom vocabulary.

#### Scenario: Create dictionary
- **WHEN** the user creates a new dictionary
- **THEN** the system SHALL create a named dictionary that the user can populate with term entries

#### Scenario: Dictionary entry
- **WHEN** the user adds an entry to a dictionary
- **THEN** the entry SHALL contain at minimum: the correct term (e.g., "TingMo", "Xcode"), and optionally common misrecognitions to match against (e.g., "听某", "婷某", "叉code")

#### Scenario: Edit and delete dictionary
- **WHEN** the user edits or deletes a dictionary
- **THEN** the system SHALL update or remove the dictionary and its entries accordingly

### Requirement: Dual correction strategy
The system SHALL apply dictionary corrections through two complementary strategies depending on whether LLM correction is enabled.

#### Scenario: LLM enabled — inject into prompt
- **WHEN** LLM correction is enabled and active dictionaries contain entries
- **THEN** the system SHALL inject the active dictionaries' terms into the LLM prompt context, instructing the LLM to use these terms when correcting the transcription

#### Scenario: LLM disabled — text replacement fallback
- **WHEN** LLM correction is disabled and active dictionaries contain entries with defined misrecognition patterns
- **THEN** the system SHALL perform text replacement on the raw transcription, matching misrecognition patterns and replacing them with the correct terms

#### Scenario: Both strategies when LLM enabled
- **WHEN** LLM correction is enabled
- **THEN** the system SHALL rely on LLM prompt injection for correction and SHALL NOT perform text replacement (to avoid double-correction)

### Requirement: Dictionary selection in Config Preset
Each Config Preset SHALL allow the user to select which dictionaries are active when the preset is in use. Dictionaries themselves are managed globally, not per-preset.

#### Scenario: Select dictionaries for preset
- **WHEN** the user edits a Config Preset
- **THEN** the system SHALL allow selecting zero or more dictionaries from the global dictionary list to be active for that preset

#### Scenario: Preset switch changes active dictionaries
- **WHEN** the user switches to a different Config Preset
- **THEN** the system SHALL activate only the dictionaries selected in that preset

### Requirement: Dictionary iCloud sync
Dictionaries SHALL be synced via iCloud for App Store version users.

#### Scenario: iCloud sync available
- **WHEN** the user is on the App Store version and signed into iCloud
- **THEN** the system SHALL sync all dictionaries and their entries across devices

#### Scenario: iCloud sync unavailable
- **WHEN** the user is on the self-compiled version or not signed into iCloud
- **THEN** dictionaries SHALL be stored locally only
