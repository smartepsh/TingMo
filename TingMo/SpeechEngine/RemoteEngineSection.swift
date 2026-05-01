import SwiftUI

/// Settings section for configuring a single remote STT provider.
///
/// One row per provider. API key is stored via `EncryptedKeyStore`, a
/// "Test" button runs `runConnectivityCheck()` and surfaces a result line.
struct RemoteEngineSection: View {
    let engine: RemoteSpeechEngine
    @Bindable var engineRegistry: EngineRegistry

    @State private var apiKey: String = ""
    @State private var isTesting = false
    @State private var lastTestResult: TestResult?
    @State private var keyHint: String?

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        Section {
            SecureField(
                String(localized: "API Key"),
                text: $apiKey,
                prompt: keyPlaceholder
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit { saveAPIKey() }

            HStack {
                Button(String(localized: "Save")) {
                    saveAPIKey()
                }
                .disabled(apiKey.isEmpty && !engine.info.isReady)

                Button(String(localized: "Clear"), role: .destructive) {
                    clearAPIKey()
                }
                .disabled(!engine.info.isReady && apiKey.isEmpty)

                Spacer()

                Button {
                    Task { await runTest() }
                } label: {
                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(String(localized: "Test Connection"))
                    }
                }
                .disabled(isTesting || !engine.info.isReady)
            }

            if let result = lastTestResult {
                switch result {
                case .success:
                    Label(String(localized: "Connection OK"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .failure(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text(engine.config.name)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(statusFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = engine.config.billingNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear(perform: loadExistingKey)
    }

    // MARK: - Actions

    private func loadExistingKey() {
        if engine.info.isReady {
            apiKey = ""
            keyHint = EncryptedKeyStore.keyHint(service: engine.config.keychainService)
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = EncryptedKeyStore.set(trimmed, for: engine.config.keychainService)
        engineRegistry.refreshRemoteEnginesReadiness()
        keyHint = EncryptedKeyStore.keyHint(service: engine.config.keychainService)
        apiKey = ""
        lastTestResult = nil
    }

    private func clearAPIKey() {
        _ = EncryptedKeyStore.delete(service: engine.config.keychainService)
        engineRegistry.refreshRemoteEnginesReadiness()
        keyHint = nil
        apiKey = ""
        lastTestResult = nil
    }

    private func runTest() async {
        isTesting = true
        defer { isTesting = false }
        if let error = await engine.runConnectivityCheck() {
            lastTestResult = .failure(error.localizedDescription)
        } else {
            lastTestResult = .success
        }
    }

    // MARK: - Status text

    private var keyPlaceholder: Text {
        if let hint = keyHint {
            return Text(hint)
        }
        return Text("")
    }

    private var statusFooter: String {
        if engine.info.isReady {
            return String(localized: "API key saved. Use 'Test Connection' to verify.")
        }
        return String(localized: "Enter an API key to enable this engine.")
    }
}
