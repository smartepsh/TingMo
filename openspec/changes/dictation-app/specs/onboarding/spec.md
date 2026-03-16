## ADDED Requirements

### Requirement: First-launch onboarding wizard
The system SHALL present a step-by-step onboarding wizard on first launch to guide the user through essential setup.

#### Scenario: Onboarding flow
- **WHEN** the application launches for the first time
- **THEN** the system SHALL present an onboarding wizard that guides the user through: granting microphone permission, granting Accessibility permission, granting screen recording permission (optional), selecting and downloading a speech recognition engine/model, and configuring the global hotkey

#### Scenario: Skip and resume
- **WHEN** the user skips the onboarding wizard
- **THEN** the system SHALL allow the user to access the same setup steps later from the settings interface

#### Scenario: Onboarding completed
- **WHEN** the user completes the onboarding wizard
- **THEN** the system SHALL mark onboarding as complete and not show it again on subsequent launches

### Requirement: Multi-language UI
The application interface SHALL support multiple languages.

#### Scenario: Supported languages (initial)
- **WHEN** the application launches
- **THEN** the system SHALL support Chinese (Simplified) and English for all UI elements, following the user's macOS system language preference

#### Scenario: Language fallback
- **WHEN** the user's system language is not Chinese or English
- **THEN** the system SHALL fall back to English

#### Scenario: Future language expansion
- **THEN** additional UI languages MAY be added in future releases
