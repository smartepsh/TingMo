## ADDED Requirements

### Requirement: Dual-mode global hotkey
The system SHALL support a single global hotkey that provides two recording modes based on press duration.

#### Scenario: Short press — toggle mode
- **WHEN** the user presses and releases the global hotkey within the short-press threshold (e.g., 300ms) and no dictation session is active
- **THEN** the system SHALL start a dictation session that continues until the next short press

#### Scenario: Short press — stop toggle
- **WHEN** the user short-presses the global hotkey while a toggle-mode dictation session is active
- **THEN** the system SHALL stop the dictation session and proceed to output (transcription → optional LLM correction → clipboard → paste)

#### Scenario: Long press — press-to-record mode
- **WHEN** the user presses and holds the global hotkey beyond the short-press threshold
- **THEN** the system SHALL continue the recording that started on key-down; when the user releases the key, the system SHALL stop recording and proceed to output

#### Scenario: Recording starts on key-down
- **WHEN** the user presses the global hotkey (regardless of intended mode)
- **THEN** the system SHALL begin recording immediately on key-down (not after the threshold), so that no audio is lost in either mode

#### Scenario: Default hotkey
- **WHEN** the application launches for the first time
- **THEN** the system SHALL register the default global hotkey (Option+D)

### Requirement: Cancel recording
The system SHALL allow the user to cancel an active toggle-mode recording, discarding the captured audio without proceeding to transcription.

#### Scenario: Cancel via ESC
- **WHEN** a toggle-mode dictation session is active and the user presses ESC (default cancel key)
- **THEN** the system SHALL immediately stop recording, discard the captured audio, and return to idle state without triggering transcription

#### Scenario: Cancel not applicable to long-press
- **WHEN** the user is in a long-press (press-to-record) dictation session
- **THEN** releasing the hotkey SHALL stop recording and proceed to output as normal; ESC has no effect during long-press recording

### Requirement: Custom hotkey configuration
The system SHALL allow users to customize the global hotkey combination.

#### Scenario: Change hotkey
- **WHEN** the user sets a new hotkey combination in settings
- **THEN** the system SHALL unregister the previous hotkey and register the new one immediately

#### Scenario: Hotkey conflict
- **WHEN** the user attempts to set a hotkey that conflicts with a system shortcut
- **THEN** the system SHALL warn the user about the potential conflict but allow them to proceed

### Requirement: Application exclusion list
The system SHALL allow users to specify applications where the global hotkey is ignored, passing the key event through to the original application.

#### Scenario: Excluded application
- **WHEN** the user presses the global hotkey while an excluded application is in the foreground
- **THEN** the system SHALL NOT intercept the key event and SHALL pass it through to the application

#### Scenario: Manage exclusion list
- **WHEN** the user opens the exclusion list settings
- **THEN** the system SHALL display a list of excluded applications with the ability to add or remove entries

### Requirement: CLI command interface
The system SHALL provide a command-line interface for triggering dictation actions.

#### Scenario: CLI toggle
- **WHEN** the user runs `tingmo toggle` in a terminal
- **THEN** the system SHALL start or stop a dictation session, same as short-pressing the global hotkey

#### Scenario: CLI start and stop
- **WHEN** the user runs `tingmo start` or `tingmo stop`
- **THEN** the system SHALL explicitly start or stop a dictation session

### Requirement: AppleScript support
The system SHALL expose dictation actions via AppleScript, enabling integration with macOS Shortcuts, Alfred, Raycast, and other automation tools.

#### Scenario: AppleScript toggle
- **WHEN** an AppleScript command tells TingMo to toggle dictation
- **THEN** the system SHALL start or stop a dictation session accordingly

### Requirement: Accessibility permission for global events
The system SHALL require Accessibility permission to monitor global keyboard events.

#### Scenario: Accessibility permission not granted
- **WHEN** the application starts without Accessibility permission
- **THEN** the system SHALL prompt the user to grant Accessibility permission in System Settings and explain why it is needed
