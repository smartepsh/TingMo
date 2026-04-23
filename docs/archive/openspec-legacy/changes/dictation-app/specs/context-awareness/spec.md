## ADDED Requirements

### Requirement: Selected text context
The system SHALL capture text that is currently selected in the active application when dictation starts, via Accessibility API.

#### Scenario: Text is selected
- **WHEN** the user starts dictation and text is selected in the active application
- **THEN** the system SHALL include the selected text as context for LLM correction

#### Scenario: No text selected
- **WHEN** the user starts dictation and no text is selected
- **THEN** the system SHALL proceed without selected text context

### Requirement: Active input field context
The system SHALL capture the full text content of the currently focused input field via Accessibility API, including text that is scrolled out of view.

#### Scenario: Input field has content
- **WHEN** the user starts dictation with a focused input field containing text
- **THEN** the system SHALL include the input field's full text as context for LLM correction

### Requirement: Active window information context
The system SHALL capture the current window title and application name via Accessibility API.

#### Scenario: Window info available
- **WHEN** the user starts dictation
- **THEN** the system SHALL include the active application name and window title as context for LLM correction

### Requirement: Clipboard content context
The system SHALL capture the current clipboard text content as context.

#### Scenario: Clipboard has text
- **WHEN** the user starts dictation and the clipboard contains text
- **THEN** the system SHALL include the clipboard text as context for LLM correction

### Requirement: Active application full-text context
The system SHALL attempt to read the full visible text content of the active application via Accessibility API deep traversal, including terminal output, browser page text, AI chat history, etc.

#### Scenario: Accessibility read succeeds
- **WHEN** the system attempts to read the active application's full text and completes within the timeout
- **THEN** the system SHALL include the retrieved text as context for LLM correction

#### Scenario: Accessibility read timeout
- **WHEN** the Accessibility API deep read exceeds the timeout (1-2 seconds)
- **THEN** the system SHALL abandon the read and fall back to screenshot context if enabled

#### Scenario: Accessibility read fails
- **WHEN** the active application does not expose text content via Accessibility API
- **THEN** the system SHALL fall back to screenshot context if enabled

### Requirement: Screenshot context
The system SHALL support capturing a screenshot of the active window/screen as context, to be sent to a multimodal LLM for understanding.

#### Scenario: Screenshot as fallback
- **WHEN** Accessibility full-text read fails or times out and screenshot context is enabled
- **THEN** the system SHALL capture a screenshot and include it as image context for LLM correction

#### Scenario: Screenshot as primary
- **WHEN** the user configures screenshot as the preferred context method
- **THEN** the system SHALL capture a screenshot for context regardless of Accessibility availability

#### Scenario: Screen recording permission
- **WHEN** screenshot context is enabled but screen recording permission is not granted
- **THEN** the system SHALL prompt the user to grant screen recording permission in System Settings

### Requirement: Context strategy configuration
The system SHALL allow users to configure which context sources are enabled and their priority (Accessibility-first + screenshot fallback, screenshot-first, or specific sources only).

#### Scenario: Context settings
- **WHEN** the user opens context settings
- **THEN** the system SHALL display toggles for each context source and the fallback strategy

### Requirement: Privacy protection
The system SHALL never read password field contents and SHALL clearly indicate what data is being captured as context.

#### Scenario: Password field detected
- **WHEN** the focused field is a password/secure text field
- **THEN** the system SHALL NOT include that field's content in the context
