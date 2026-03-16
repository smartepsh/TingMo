## ADDED Requirements

### Requirement: Automatic clipboard-based text injection
The system SHALL automatically inject the final text (transcription, optionally corrected by LLM) into the currently focused application by writing to the clipboard and simulating a Cmd+V paste keystroke. No user confirmation step is required.

#### Scenario: Successful text injection
- **WHEN** the final text output is ready (after transcription and optional LLM correction)
- **THEN** the system SHALL save the current clipboard content, write the final text to the clipboard, simulate Cmd+V, and restore the original clipboard content

#### Scenario: No focused text field
- **WHEN** the final text is ready but no text input is focused
- **THEN** the system SHALL still write the text to the clipboard (the user can manually paste later)

### Requirement: Clipboard preservation
The system SHALL preserve the user's clipboard content across text injection operations.

#### Scenario: Clipboard restored after injection
- **WHEN** text injection completes
- **THEN** the system SHALL restore the clipboard to its previous content after a user-configurable delay (default: 500ms)

#### Scenario: Configurable restore delay
- **WHEN** the user adjusts the clipboard restore delay in settings
- **THEN** the system SHALL use the configured delay for all subsequent text injection operations

#### Scenario: Multiple clipboard types
- **WHEN** the clipboard contains multiple data types (text, images, etc.) before injection
- **THEN** the system SHALL preserve and restore all clipboard data types
