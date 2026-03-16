## ADDED Requirements

### Requirement: Audio input device enumeration
The system SHALL enumerate all available audio input devices from the system via CoreAudio and present them to the user.

#### Scenario: List available devices
- **WHEN** the user opens audio device settings or a device selection UI
- **THEN** the system SHALL display all currently connected audio input devices with their name and online/offline status

### Requirement: Device UID persistence
The system SHALL persist audio input devices using CoreAudio's `kAudioDevicePropertyDeviceUID`, allowing the system to remember devices across reconnections.

#### Scenario: New device connected
- **WHEN** an audio input device is connected that the system has not seen before
- **THEN** the system SHALL record the device's UID and display name for future reference

#### Scenario: Known device reconnected
- **WHEN** a previously seen device is reconnected
- **THEN** the system SHALL recognize it by UID and restore its position in the user's priority list

#### Scenario: Historical device display
- **WHEN** the user views the device list
- **THEN** the system SHALL show both currently online devices and previously seen (offline) devices, with offline devices visually distinguished (e.g., greyed out)

#### Scenario: Remove historical device
- **WHEN** the user removes a historical device from the list
- **THEN** the system SHALL delete the stored UID and device info, and the device will be treated as new if reconnected

### Requirement: Device priority ordering
The system SHALL allow users to reorder the device list to define a priority order. This priority list is managed locally per device and is NOT synced via iCloud.

#### Scenario: Reorder devices
- **WHEN** the user drags to reorder devices in the device list
- **THEN** the system SHALL persist the new order as the device priority list

#### Scenario: Priority list usage
- **WHEN** the active Config Preset's device selection mode is "priority"
- **THEN** the system SHALL iterate through the local priority list in order and use the first device that is currently online

### Requirement: Device online status monitoring
The system SHALL monitor audio input device connection and disconnection events in real time via CoreAudio property listeners.

#### Scenario: Device connected during app runtime
- **WHEN** a new audio input device is connected while the app is running
- **THEN** the system SHALL update the device list to reflect the newly available device

#### Scenario: Device disconnected during app runtime (not recording)
- **WHEN** an audio input device is disconnected while the app is NOT actively recording
- **THEN** the system SHALL update the device list to show the device as offline

### Requirement: Device disconnection during recording
The system SHALL handle audio device disconnection during an active recording session gracefully.

#### Scenario: Active device disconnected during recording
- **WHEN** the currently active audio input device is disconnected during an active dictation session
- **THEN** the system SHALL immediately stop recording, notify the user that the microphone has been disconnected, and send the already-captured audio through the normal transcription pipeline
