import Foundation

// M3 persisted a single global LLMConfig under `LLMSettingsStore.config`.
// M4 migrates that value into ConfigPresetStore's default preset; this file is
// intentionally left as a small historical marker because the migration key is
// still part of the app's compatibility surface.
