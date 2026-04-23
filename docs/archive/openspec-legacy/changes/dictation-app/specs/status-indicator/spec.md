## ADDED Requirements

### Requirement: Three display modes for dictation status
The system SHALL support three display modes for the dictation status indicator, selectable by the user in settings.

#### Scenario: Mode selection
- **WHEN** the user selects a display mode in settings
- **THEN** the system SHALL use the selected mode for all subsequent dictation sessions

#### Scenario: Multi-monitor display
- **WHEN** multiple displays are connected
- **THEN** the status indicator SHALL appear on the display that contains the currently focused window

### Requirement: Notch mode (default)
The system SHALL support a Notch display mode that embeds the dictation status indicator into the macOS camera notch area, showing a waveform animation during active dictation. When space permits, it SHALL also display transcription preview text.

#### Scenario: Notch mode on device with notch
- **WHEN** dictation is active on a device with a camera notch and Notch mode is selected
- **THEN** the system SHALL display a waveform animation in the notch area

#### Scenario: Notch mode preview text
- **WHEN** dictation is active in Notch mode and the engine supports streaming
- **THEN** the system SHALL display transcription preview text alongside the waveform if space allows

#### Scenario: Default mode selection
- **WHEN** the application launches for the first time
- **THEN** the system SHALL default to Notch mode

### Requirement: Top-center mode
The system SHALL support a top-center display mode that shows the dictation status indicator at the top center of the active screen, for devices without a camera notch.

#### Scenario: Top-center display
- **WHEN** dictation is active and top-center mode is selected
- **THEN** the system SHALL display a waveform animation at the top center of the active screen

#### Scenario: Auto-fallback from Notch
- **WHEN** Notch mode is selected but the device has no camera notch
- **THEN** the system SHALL automatically fall back to top-center mode

### Requirement: Floating window mode
The system SHALL support an independent floating window mode that displays the dictation status and transcription preview text.

#### Scenario: Floating window display
- **WHEN** dictation is active and floating window mode is selected
- **THEN** the system SHALL display a floating window with waveform animation and transcription preview text

#### Scenario: Floating window stays on top
- **WHEN** the floating window is displayed
- **THEN** the window SHALL remain on top of all other windows without stealing keyboard focus

#### Scenario: Floating window appearance
- **WHEN** the floating window is displayed
- **THEN** the window SHALL have a semi-transparent background, rounded corners, and use the system font

### Requirement: Waveform animation
The system SHALL display a waveform animation in all three display modes to indicate active dictation.

#### Scenario: Animation during recording
- **WHEN** audio is being captured during a dictation session
- **THEN** the system SHALL display an animated waveform that responds to audio input levels

#### Scenario: Processing state
- **WHEN** audio capture has stopped and the system is waiting for transcription/LLM results (non-streaming engine)
- **THEN** the system SHALL display a processing/waiting indicator instead of the waveform
