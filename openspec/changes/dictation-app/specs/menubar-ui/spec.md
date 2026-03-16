## ADDED Requirements

### Requirement: Menu bar icon
The system SHALL display a persistent icon in the macOS menu bar indicating the application status.

#### Scenario: Idle state display
- **WHEN** no dictation session is active
- **THEN** the system SHALL display a microphone icon in the menu bar in its default (inactive) state

#### Scenario: Active dictation display
- **WHEN** a dictation session is active
- **THEN** the system SHALL display the menu bar icon in an active/recording state (visually distinct from idle)

### Requirement: Menu bar dropdown
The system SHALL provide a dropdown menu when the menu bar icon is clicked.

#### Scenario: Menu contents
- **WHEN** the user clicks the menu bar icon
- **THEN** the system SHALL display a dropdown menu with: current status, active Config Preset switcher, active audio device display, settings access, and quit option

### Requirement: No Dock icon
The system SHALL run as a menu bar-only application without showing an icon in the Dock.

#### Scenario: Application launch
- **WHEN** the application launches
- **THEN** the application SHALL NOT appear in the Dock or the Cmd+Tab application switcher

### Requirement: Settings interface
The system SHALL provide a settings view accessible from the menu bar dropdown.

#### Scenario: Settings access
- **WHEN** the user clicks "Settings" in the menu bar dropdown
- **THEN** the system SHALL display a settings window with sections for: Config Preset management, audio device management, engine/model management, hotkey configuration, application exclusion list, LLM correction configuration, context awareness settings, status indicator display mode, and launch at login toggle
