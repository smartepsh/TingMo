import SwiftUI

struct STTInstanceSettingsSection: View {
    @Bindable var instanceStore: STTInstanceStore
    @Bindable var engineRegistry: EngineRegistry
    @Bindable var presetStore: ConfigPresetStore

    @State private var apiKeys: [UUID: String] = [:]
    @State private var pendingDeleteID: UUID?
    @State private var activeDeleteID: UUID?
    @State private var renamingID: UUID?
    @State private var renameText: String = ""
    @State private var expandedInstanceID: UUID?
    @State private var isTesting: [UUID: Bool] = [:]
    @State private var testResults: [UUID: TestResult] = [:]

    enum TestResult {
        case success
        case failure(String)
    }

    private var activeInstanceID: UUID? {
        let engineID = presetStore.defaultPreset.speechEngineID
        guard engineID.hasPrefix("stt-instance-") else { return nil }
        let uuidString = engineID.replacingOccurrences(of: "stt-instance-", with: "")
        return UUID(uuidString: uuidString)
    }

    var body: some View {
        Section {
            ForEach(instanceStore.instances) { instance in
                DisclosureGroup(isExpanded: expandedBinding(for: instance.id)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker(String(localized: "Provider"), selection: providerBinding(for: instance.id)) {
                            ForEach(STTProviderID.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }

                        SecureField(
                            String(localized: "API Key"),
                            text: apiKeyBinding(for: instance.id),
                            prompt: keyPlaceholder(for: instance)
                        )
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveAPIKey(for: instance.id) }

                        HStack {
                            Button(String(localized: "Save")) {
                                saveAPIKey(for: instance.id)
                            }
                            .disabled((apiKeys[instance.id] ?? "").isEmpty && !instanceStore.hasAPIKey(for: instance))

                            Button(String(localized: "Clear"), role: .destructive) {
                                clearAPIKey(for: instance)
                            }
                            .disabled(!instanceStore.hasAPIKey(for: instance) && (apiKeys[instance.id] ?? "").isEmpty)

                            Spacer()

                            Button {
                                Task { await runTest(for: instance) }
                            } label: {
                                if isTesting[instance.id, default: false] {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text(String(localized: "Test Connection"))
                                }
                            }
                            .disabled(isTesting[instance.id, default: false] || !instanceStore.hasAPIKey(for: instance))
                        }

                        if let result = testResults[instance.id] {
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
                    }
                    .padding(.vertical, 4)
                } label: {
                    HStack(spacing: 6) {
                        Text(instance.displayName.isEmpty ? String(localized: "Untitled") : instance.displayName)
                            .lineLimit(1)
                            .foregroundStyle(instance.displayName.isEmpty ? .secondary : .primary)
                        Button {
                            renameText = instance.displayName
                            renamingID = instance.id
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .popover(isPresented: renameBinding(for: instance.id)) {
                            renamePopover(for: instance)
                        }
                        Spacer()
                        if activeInstanceID == instance.id {
                            Text(String(localized: "Active"))
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.12), in: Capsule())
                        }
                        Text(instance.provider.displayName)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        deleteButton(for: instance)
                    }
                }
            }
        } header: {
            HStack {
                Text("Remote STT Providers")
                Spacer()
                Menu {
                    ForEach(STTProviderID.allCases) { provider in
                        Button(provider.defaultInstanceName) {
                            let instance = instanceStore.addInstance(provider: provider)
                            apiKeys[instance.id] = ""
                            expandedInstanceID = instance.id
                            engineRegistry.refreshRemoteSTTEngines()
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
            }
        } footer: {
            Text(String(localized: "Remote STT providers store reusable API connections. Presets reference these by name."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bindings

    private func expandedBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedInstanceID == id },
            set: { expandedInstanceID = $0 ? id : nil }
        )
    }

    private func renameBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { renamingID == id },
            set: { if !$0 { renamingID = nil } }
        )
    }

    private func providerBinding(for id: UUID) -> Binding<STTProviderID> {
        Binding(
            get: { instanceStore.instance(id: id)?.provider ?? .groq },
            set: { provider in
                guard var instance = instanceStore.instance(id: id) else { return }
                guard instance.provider != provider else { return }
                let oldProvider = instance.provider
                _ = instanceStore.clearAPIKey(for: instance)
                instance.provider = provider
                let usedDefaultName = instance.displayName == oldProvider.defaultInstanceName
                    || instance.displayName == ""
                if usedDefaultName {
                    instance.displayName = provider.defaultInstanceName
                }
                instanceStore.upsert(instance)
                apiKeys[id] = ""
                testResults[id] = nil
            }
        )
    }

    private func apiKeyBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { apiKeys[id, default: ""] },
            set: { apiKeys[id] = $0 }
        )
    }

    private func keyPlaceholder(for instance: STTInstance) -> Text {
        if instanceStore.hasAPIKey(for: instance),
           let hint = EncryptedKeyStore.keyHint(service: instance.keychainService) {
            return Text(hint)
        }
        return Text("")
    }

    // MARK: - Actions

    private func saveAPIKey(for id: UUID) {
        guard let instance = instanceStore.instance(id: id) else { return }
        guard instanceStore.saveAPIKey(apiKeys[id, default: ""], for: instance) else { return }
        apiKeys[id] = ""
        engineRegistry.refreshRemoteEnginesReadiness()
    }

    private func clearAPIKey(for instance: STTInstance) {
        _ = instanceStore.clearAPIKey(for: instance)
        apiKeys[instance.id] = nil
        testResults[instance.id] = nil
        engineRegistry.refreshRemoteEnginesReadiness()
    }

    private func runTest(for instance: STTInstance) async {
        isTesting[instance.id] = true
        defer { isTesting[instance.id] = false }

        let engine = RemoteSpeechEngine(instance: instance)
        if let error = await engine.runConnectivityCheck() {
            testResults[instance.id] = .failure(error.localizedDescription)
        } else {
            testResults[instance.id] = .success
        }
    }

    private func commitRename(_ id: UUID) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var instance = instanceStore.instance(id: id) else {
            renamingID = nil
            return
        }
        instance.displayName = trimmed
        instanceStore.upsert(instance)
        renamingID = nil
    }

    @ViewBuilder
    private func renamePopover(for instance: STTInstance) -> some View {
        VStack(spacing: 8) {
            TextField(instance.displayName, text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { commitRename(instance.id) }
            HStack {
                Button(String(localized: "Cancel")) {
                    renamingID = nil
                }
                .keyboardShortcut(.cancelAction)
                Button(String(localized: "Rename")) {
                    commitRename(instance.id)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func deleteButton(for instance: STTInstance) -> some View {
        let isActive = activeInstanceID == instance.id
        let isPending = pendingDeleteID == instance.id
        Button {
            if isActive {
                activeDeleteID = instance.id
            } else if isPending {
                deleteInstance(instance.id)
            } else {
                pendingDeleteID = instance.id
            }
        } label: {
            Image(systemName: "trash")
                .foregroundStyle(isPending ? .red : .secondary)
        }
        .buttonStyle(.borderless)
        .confirmationDialog(
            String(localized: "Delete this provider?"),
            isPresented: Binding(
                get: { activeDeleteID == instance.id },
                set: { if !$0 { activeDeleteID = nil } }
            ),
            presenting: instance
        ) { _ in
            Button(String(localized: "Delete"), role: .destructive) {
                deleteInstance(instance.id)
            }
        } message: { _ in
            Text(String(localized: "This provider is active in your preset. Deleting it will reset the Speech Engine."))
        }
        .onHover { inside in
            if !inside && isPending {
                pendingDeleteID = nil
            }
        }
    }

    private func deleteInstance(_ id: UUID) {
        let instanceID = "stt-instance-\(id.uuidString)"
        guard instanceStore.deleteInstance(id: id) else { return }
        presetStore.replaceSpeechEngineSelection(
            deletedID: instanceID,
            fallbackID: ConfigPreset.defaultSpeechEngineID
        )
        apiKeys[id] = nil
        testResults[id] = nil
        pendingDeleteID = nil
        engineRegistry.refreshRemoteSTTEngines()
    }
}
