import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Vision

struct ScreenshotOCRCollector {
    var maxCharacters: Int

    init(maxCharacters: Int = 1_200) {
        self.maxCharacters = maxCharacters
    }

    func collect() -> String? {
        guard let image = captureFrontWindow() else { return nil }
        let text = recognizeText(in: image)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    func captureAndRecognize(targetPID: pid_t? = nil) async -> String? {
        guard let image = await captureFrontWindowAsync(targetPID: targetPID) else { return nil }
        let text = recognizeText(in: image)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private func captureFrontWindowAsync(targetPID: pid_t? = nil) async -> CGImage? {
        let pid: pid_t
        if let targetPID {
            pid = targetPID
        } else if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            pid = frontmostApp.processIdentifier
        } else {
            return nil
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.owningApplication?.processID == pid }) else { return nil }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width)
            config.height = Int(window.frame.height)
            config.showsCursor = false

            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            return nil
        }
    }

    private func captureFrontWindow() -> CGImage? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontmostApp.processIdentifier

        let semaphore = DispatchSemaphore(value: 0)
        var result: CGImage?

        Task {
            defer { semaphore.signal() }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let window = content.windows.first(where: { $0.owningApplication?.processID == pid }) else { return }

                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                config.width = Int(window.frame.width)
                config.height = Int(window.frame.height)
                config.showsCursor = false

                result = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            } catch {
                // Silent failure — Screen Recording permission may not be granted
            }
        }

        semaphore.wait()
        return result
    }

    private func recognizeText(in image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results else { return nil }

        let recognized = observations.compactMap { observation -> String? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return candidate.string
        }.joined(separator: "\n")

        let trimmed = ContextTextCleaner.clean(recognized)
        guard !trimmed.isEmpty else { return nil }

        if looksSensitive(trimmed) { return nil }

        return String(trimmed.prefix(maxCharacters))
    }

    private func looksSensitive(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let secretWords = ["password", "passwd", "secret", "api_key", "apikey", "token", "bearer "]
        if secretWords.contains(where: { lowercased.contains($0) }) {
            return true
        }

        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.count >= 32,
           compact.range(of: #"^[A-Za-z0-9_\-\.=]+$"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }
}
