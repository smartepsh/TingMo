## ADDED Requirements

### Requirement: Optional LLM correction post-processing
The system SHALL provide an optional LLM correction step that processes transcription results through a large language model before output. This feature SHALL be disabled by default.

#### Scenario: LLM correction enabled
- **WHEN** LLM correction is enabled and a transcription completes
- **THEN** the system SHALL send the transcription text (with available context) to the configured LLM and use the corrected result as the final output

#### Scenario: LLM correction disabled
- **WHEN** LLM correction is disabled and a transcription completes
- **THEN** the system SHALL use the raw transcription result directly as the final output

### Requirement: Multiple LLM API format support
The system SHALL support multiple LLM API formats for the correction step.

#### Scenario: OpenAI compatible API
- **WHEN** the user configures an OpenAI compatible endpoint (covering OpenAI, Groq, Ollama, proxy services, etc.)
- **THEN** the system SHALL communicate with the endpoint using the OpenAI chat completions API format

#### Scenario: Anthropic API
- **WHEN** the user configures an Anthropic endpoint
- **THEN** the system SHALL communicate with the endpoint using the Anthropic messages API format

### Requirement: User-configurable LLM parameters
The system SHALL allow users to configure all LLM correction parameters including API endpoint, API Key, model, system prompt, and temperature.

#### Scenario: Custom system prompt
- **WHEN** the user sets a custom system prompt for LLM correction
- **THEN** the system SHALL use that prompt when sending transcription text to the LLM

#### Scenario: API Key configuration
- **WHEN** the user provides an API Key for a selected LLM provider
- **THEN** the system SHALL store the key securely in the local Keychain (not synced via iCloud) and use it for all correction requests

### Requirement: Integration with Config Preset
LLM correction parameters (provider, endpoint, API Key, model, system prompt, temperature, enabled/disabled) SHALL be managed as part of the Config Preset system (see `config-preset` capability). Switching Config Presets will apply the corresponding LLM correction configuration.

#### Scenario: Preset switch affects LLM config
- **WHEN** the user switches to a different Config Preset
- **THEN** the system SHALL apply that preset's LLM correction settings (including whether correction is enabled, which provider/model to use, and which prompt to apply)
