## ADDED Requirements

### Requirement: Transcription history
The system SHALL maintain a local history of all transcription results, allowing users to review and copy past transcriptions.

#### Scenario: History entry creation
- **WHEN** a transcription (with or without LLM correction) completes successfully
- **THEN** the system SHALL create a history entry containing: timestamp, final output text (LLM-corrected if enabled, otherwise raw transcription), raw transcription text, engine used, audio device used, active Config Preset name, active application name, and dictation duration

#### Scenario: History list display
- **WHEN** the user opens the history view
- **THEN** the system SHALL display a chronological list of past transcriptions, primarily showing the final output text and timestamp

#### Scenario: Copy from history
- **WHEN** the user selects a history entry
- **THEN** the system SHALL provide a quick action to copy the final output text to the clipboard

### Requirement: Audio file retention
The system SHALL retain audio files for a limited number of recent transcriptions to support retry and review.

#### Scenario: Audio retention limit
- **WHEN** a new dictation session completes
- **THEN** the system SHALL retain the audio file and automatically delete audio files beyond the retention limit (configurable, default: last 3 sessions)

#### Scenario: Audio retention for failed transcriptions
- **WHEN** a transcription fails (network error, engine error)
- **THEN** the system SHALL retain the audio file as part of the history entry, allowing the user to retry with a different engine or after network recovery

#### Scenario: Retry from history
- **WHEN** the user selects a history entry that has a retained audio file
- **THEN** the system SHALL allow re-transcribing the audio with the current or a different engine

#### Scenario: User-configurable retention
- **WHEN** the user adjusts the audio retention count in settings
- **THEN** the system SHALL apply the new limit, deleting excess audio files from oldest entries first

### Requirement: History storage
History entries (text data) SHALL be stored locally. Audio files SHALL be stored in a dedicated local directory.

#### Scenario: iCloud sync for history (optional)
- **WHEN** the user enables history sync in settings (App Store version)
- **THEN** the system SHALL sync history text entries via iCloud; audio files are NOT synced

#### Scenario: No iCloud sync
- **WHEN** the user disables history sync or is on the self-compiled version
- **THEN** history entries SHALL be stored locally only

### Requirement: History and storage cleanup
The system SHALL provide users with the ability to manage and clean up stored data.

#### Scenario: Clear all history
- **WHEN** the user chooses to clear all history in settings
- **THEN** the system SHALL delete all history entries and associated audio files

#### Scenario: Delete individual entry
- **WHEN** the user deletes a single history entry
- **THEN** the system SHALL remove that entry and its associated audio file (if any)

#### Scenario: Storage overview
- **WHEN** the user opens the storage management section in settings
- **THEN** the system SHALL display the storage usage for: speech recognition models, retained audio files, and history database
