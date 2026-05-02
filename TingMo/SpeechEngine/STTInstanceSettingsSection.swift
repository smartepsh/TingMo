import SwiftUI

struct STTInstanceSettingsSection: View {
    @Bindable var instanceStore: STTInstanceStore
    @Bindable var engineRegistry: EngineRegistry
    @Bindable var presetStore: ConfigPresetStore

    @State private var apiKeys: [UUID: String] = [:]
    @State private var draftAPIKeys: [UUID: String] = [:]
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
                        SecureField(
                            String(localized: "API Key"),
                            text: apiKeyBinding(for: instance.id),
                            prompt: keyPlaceholder(for: instance)
                        )
                        .textFieldStyle(.roundedBorder)

                        HStack {
                            Spacer()

                            if !instanceIsVerified(instance) {
                                Button {
                                    Task { await runTest(for: instance) }
                                } label: {
                                    if isTesting[instance.id, default: false] {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        HStack(spacing: 4) {
                                            Image(systemName: "bolt.fill")
                                                .font(.caption)
                                            Text(String(localized: "Test"))
                                                .font(.caption)
                                                .fontWeight(.medium)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .foregroundStyle(.tint)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(.tint, lineWidth: 1)
                                        )
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(isTesting[instance.id, default: false]
                                    || (!instanceStore.hasAPIKey(for: instance)
                                        && (draftAPIKeys[instance.id] ?? "").isEmpty))
                            }
                        }

                        if let result = testResults[instance.id] {
                            if case .failure(let message) = result {
                                Label(message, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    instanceRowLabel(instance)
                }
            }
        } header: {
            HStack {
                Text("Remote Provider")
                Spacer()
                Menu {
                    ForEach(STTProviderID.allCases) { provider in
                        Button(provider.defaultInstanceName) {
                            let instance = instanceStore.addInstance(provider: provider)
                            apiKeys[instance.id] = ""
                            draftAPIKeys[instance.id] = ""
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
            Text(String(localized: "Remote providers store reusable API connections. Presets reference these by name."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: expandedInstanceID) { _, newID in
            flushPreviousDrafts(keeping: newID)
        }
        .onDisappear {
            flushAllDrafts()
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

    private func apiKeyBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { draftAPIKeys[id, default: ""] },
            set: { newValue in
                let oldValue = draftAPIKeys[id, default: ""]
                if newValue != oldValue {
                    draftAPIKeys[id] = newValue
                    clearVerifiedFingerprint(for: id)
                }
            }
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

    private func runTest(for instance: STTInstance) async {
        guard isTesting[instance.id, default: false] == false else { return }
        isTesting[instance.id] = true
        defer { isTesting[instance.id] = false }

        flushDrafts(for: instance.id)

        guard let freshInstance = instanceStore.instance(id: instance.id) else { return }

        let engine = RemoteSpeechEngine(instance: freshInstance)
        if let error = await engine.runConnectivityCheck() {
            testResults[freshInstance.id] = .failure(error.localizedDescription)
            clearVerifiedFingerprint(for: freshInstance.id)
        } else {
            testResults[freshInstance.id] = .success
            var updated = freshInstance
            let hint = EncryptedKeyStore.keyHint(service: freshInstance.keychainService)
            updated.verifiedFingerprint = updated.computeFingerprint(apiKeyHint: hint)
            instanceStore.upsert(updated)
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

    // MARK: - Instance Row Label

    @ViewBuilder
    private func instanceRowLabel(_ instance: STTInstance) -> some View {
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
                Text(String(localized: "In Preset"))
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.12), in: Capsule())
            }
            if instanceIsVerified(instance) {
                Text(String(localized: "✓ Verified"))
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.12), in: Capsule())
            }
            Text(instance.provider.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.12), in: Capsule())
            deleteButton(for: instance)
        }
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
        draftAPIKeys[id] = nil
        testResults[id] = nil
        pendingDeleteID = nil
        engineRegistry.refreshRemoteSTTEngines()
    }

    // MARK: - Verification

    private func instanceIsVerified(_ instance: STTInstance) -> Bool {
        guard let stored = instance.verifiedFingerprint, !stored.isEmpty else { return false }
        let hint = EncryptedKeyStore.keyHint(service: instance.keychainService)
        return stored == instance.computeFingerprint(apiKeyHint: hint)
    }

    private func clearVerifiedFingerprint(for id: UUID) {
        guard var instance = instanceStore.instance(id: id),
              instance.verifiedFingerprint != nil else { return }
        instance.clearVerified()
        instanceStore.upsert(instance)
    }

    // MARK: - Draft Flush

    private func flushDrafts(for id: UUID) {
        if let key = draftAPIKeys.removeValue(forKey: id) {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                guard let instance = instanceStore.instance(id: id) else { return }
                _ = instanceStore.clearAPIKey(for: instance)
                testResults[id] = nil
            } else {
                guard let instance = instanceStore.instance(id: id) else { return }
                _ = instanceStore.saveAPIKey(trimmed, for: instance)
            }
            engineRegistry.refreshRemoteEnginesReadiness()
        }
    }

    private func flushPreviousDrafts(keeping newID: UUID?) {
        let allIDs = Set(draftAPIKeys.keys)
        for id in allIDs where id != newID {
            flushDrafts(for: id)
        }
    }

    private func flushAllDrafts() {
        let ids = Set(draftAPIKeys.keys)
        for id in ids {
            flushDrafts(for: id)
        }
    }
}
