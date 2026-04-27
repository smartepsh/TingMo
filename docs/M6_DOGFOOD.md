# M6 Dogfood Notes

## Automated Verification

- `scripts/test_config_preset.swift`: validates the default Preset work-configuration model, LLM Instance resolution, stale-reference cleanup, legacy config migration, and legacy Keychain slot copy into an instance-scoped slot.
- `scripts/test_llm_instances.swift`: validates reusable LLM Instance persistence and per-instance Keychain operations.
- `xcodebuild -project "TingMo.xcodeproj" -scheme "TingMo" -configuration Debug -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build`: validates the app compiles without local signing requirements.

## Manual Dogfood Checklist

- Open Settings and confirm areas appear in this order: Presets, Speech, LLM Instances, Behavior, Advanced.
- Create or edit at least one LLM Instance, save an API key, then confirm the Preset only selects the instance and does not expose API key editing.
- Open the menu bar item and confirm the first row is the recording action.
- Confirm the menu contains `Preset: <name>`, then Language, Recognition Engine, and Correction Engine submenus under `<name> Settings`.
- Change Language, Recognition Engine, and Correction Engine from the menu, reopen Settings, and confirm the default Preset reflects those selections.
- Run a short dictation with LLM correction disabled and confirm raw transcription still injects.
- Run a short dictation with LLM correction enabled and a configured LLM Instance, then confirm the pipeline uses the Preset-selected instance.
- Delete a selected LLM Instance or imported speech model and confirm the Preset falls back to a valid remaining selection.

## Keychain Notes

- LLM API key values stay in macOS Keychain and are never encoded into Preset JSON or UserDefaults.
- M6 uses instance-scoped Keychain services like `tingmo.llm.instance.<uuid>` so multiple instances for the same provider can hold independent API keys.
- M6 does not enable `kSecAttrSynchronizable`; API keys remain local to the Mac.
- Repeated Keychain prompts during development usually indicate unstable debug signing, a changed bundle identity, or a missing local signing keychain. Run `./scripts/setup-local-signing.sh` and rebuild with the stable local signing identity before granting macOS privacy permissions again.
