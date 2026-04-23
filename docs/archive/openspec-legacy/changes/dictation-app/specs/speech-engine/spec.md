## ADDED Requirements

### Requirement: Pluggable speech recognition engine architecture
The system SHALL provide a unified engine protocol that all speech recognition engines implement, allowing users to browse, download, and switch between engines from a model list.

#### Scenario: Engine list display
- **WHEN** the user opens the engine/model settings
- **THEN** the system SHALL display a list of all available engines with their name, type (local/remote), supported languages, model size, and download status

#### Scenario: Switch engine
- **WHEN** the user selects a different engine from the list
- **THEN** the system SHALL use the selected engine for all subsequent dictation sessions

### Requirement: WhisperKit local engine support
The system SHALL support WhisperKit as a local speech recognition engine with multiple Whisper model variants (tiny, base, small, medium, large-v2, large-v3) using Core ML acceleration.

#### Scenario: Model download
- **WHEN** the user selects a WhisperKit model that is not yet downloaded
- **THEN** the system SHALL download the model from the configured download source and show download progress

#### Scenario: Custom download source
- **WHEN** the user has configured a custom model download base URL in settings
- **THEN** the system SHALL use the custom URL (via WhisperKit's `downloadBase` parameter) instead of the default Hugging Face source

#### Scenario: Local model import
- **WHEN** the user imports a local model folder (via file picker or drag-and-drop)
- **THEN** the system SHALL validate that the folder contains the required `.mlmodelc` files (MelSpectrogram, AudioEncoder, TextDecoder, etc.), copy the folder into TingMo's model directory (`~/Library/Application Support/TingMo/Models/`), and make the model available in the engine list

#### Scenario: Invalid model import
- **WHEN** the user imports a folder that does not contain valid WhisperKit model files
- **THEN** the system SHALL display an error message indicating which required files are missing

#### Scenario: WhisperKit transcription
- **WHEN** the user starts dictation with a WhisperKit engine selected
- **THEN** the system SHALL capture audio, perform on-device recognition using the selected model with Core ML acceleration, and emit transcription results

#### Scenario: WhisperKit streaming
- **WHEN** WhisperKit is the active engine and supports streaming for the selected model
- **THEN** the system SHALL emit partial transcription results in real-time during dictation

### Requirement: Apple Speech Framework engine support
The system SHALL support Apple Speech Framework (SFSpeechRecognizer) as a local engine option that requires zero download.

#### Scenario: Apple Speech as zero-download option
- **WHEN** the user selects Apple Speech Framework from the engine list
- **THEN** the system SHALL use the system's built-in speech recognizer with no additional download required

#### Scenario: Apple Speech streaming
- **WHEN** Apple Speech Framework is the active engine
- **THEN** the system SHALL emit real-time partial transcription results with minimal latency

### Requirement: Parakeet model support
The system SHALL support NVIDIA Parakeet models (via Argmax SDK / CoreML) as a local engine option, marked as English-only.

#### Scenario: Parakeet language limitation
- **WHEN** the user views the Parakeet engine in the model list
- **THEN** the system SHALL clearly indicate that Parakeet supports English only

#### Scenario: Parakeet transcription
- **WHEN** the user starts dictation with Parakeet selected
- **THEN** the system SHALL perform on-device recognition using the Parakeet CoreML model

### Requirement: Remote engine support
The system SHALL support remote speech recognition APIs (Groq, ElevenLabs, etc.) where the user provides their own API Key.

#### Scenario: Remote engine configuration
- **WHEN** the user selects a remote engine
- **THEN** the system SHALL require the user to provide an API Key and optional endpoint configuration

#### Scenario: Remote engine transcription
- **WHEN** the user starts dictation with a remote engine selected
- **THEN** the system SHALL record audio to a file, send it to the remote API after recording stops, and return the transcription result

#### Scenario: Remote engine no streaming
- **WHEN** a remote engine is active during dictation
- **THEN** the system SHALL display a waiting/processing state instead of real-time preview (no streaming for remote engines)

#### Scenario: Network failure with remote engine
- **WHEN** a remote engine transcription fails due to network error
- **THEN** the system SHALL retain the recorded audio file and notify the user, allowing them to retry or switch to a different engine

### Requirement: Audio file retention for failed transcriptions
The system SHALL retain audio files from failed transcription attempts (network errors, engine errors) to allow retry.

#### Scenario: Retained audio retry
- **WHEN** the user retries a failed transcription from history
- **THEN** the system SHALL re-send the retained audio file to the selected engine

#### Scenario: Retained audio limit
- **THEN** the system SHALL retain audio files for the most recent failed transcriptions only (not indefinitely)

### Requirement: Multi-language support
The system SHALL support multiple languages for speech recognition, depending on the selected engine's capabilities.

#### Scenario: Language selection
- **WHEN** the user selects a language from settings
- **THEN** the system SHALL use the selected language for subsequent recognition sessions

#### Scenario: Engine language compatibility
- **WHEN** the user selects a language not supported by the current engine
- **THEN** the system SHALL warn the user and suggest compatible engines

### Requirement: Microphone permission handling
The system SHALL request microphone permission on first use and handle denial gracefully.

#### Scenario: Permission granted
- **WHEN** the user grants microphone permission
- **THEN** the system SHALL proceed with normal dictation functionality

#### Scenario: Permission denied
- **WHEN** the user denies microphone permission
- **THEN** the system SHALL display a clear message explaining why the permission is needed and how to enable it in System Settings

### Requirement: Audio format adaptation
The system SHALL handle audio format conversion between the capture format and each engine's required format (e.g., sample rate, channel count, encoding).

#### Scenario: Engine requires specific format
- **WHEN** the active engine requires a specific audio format (e.g., 16kHz mono for WhisperKit)
- **THEN** the system SHALL convert the captured audio to the required format before passing it to the engine

### Requirement: Resource management
The system SHALL release speech recognition resources when not actively dictating to minimize memory and CPU usage.

#### Scenario: Idle state
- **WHEN** no dictation session is active
- **THEN** the system SHALL NOT hold any active audio capture session or loaded recognition model in memory
