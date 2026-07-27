import AppKit
import Observation
import SwiftUI

/// Manages the status indicator window across all display modes.
@Observable
final class StatusIndicatorManager {
    var mode: StatusIndicatorMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "StatusIndicator.mode")
            if isShowing { hide(); show() }
        }
    }

    var audioLevel: Float = 0
    var previewText: String = ""
    var isProcessing: Bool = false
    /// When non-nil, the indicator renders an error state. Auto-cleared
    /// after `errorDisplayDuration` by `showError(_:)`.
    var errorMessage: String?

    /// How long a flashed error stays visible before the indicator hides.
    static let errorDisplayDuration: TimeInterval = 3.0

    private var errorHideTask: Task<Void, Never>?

    /// How far (in points) the notch bar extends beyond each side of the physical notch.
    static let notchSideExtension: CGFloat = 34

    private(set) var isShowing = false
    private var panel: NSPanel?

    init() {
        let saved = UserDefaults.standard.string(forKey: "StatusIndicator.mode") ?? StatusIndicatorMode.notch.rawValue
        mode = StatusIndicatorMode(rawValue: saved) ?? .notch
    }

    func show() {
        errorHideTask?.cancel()
        let wasShowingError = errorMessage != nil
        errorMessage = nil
        guard !isShowing else {
            if wasShowingError { recreatePanel() }
            return
        }
        isShowing = true
        createPanel()
    }

    func hide() {
        errorHideTask?.cancel()
        errorMessage = nil
        isShowing = false
        panel?.orderOut(nil)
        panel = nil
    }

    func updateAudioLevel(_ level: Float) {
        audioLevel = level
    }

    func updatePreviewText(_ text: String) {
        previewText = text
    }

    func setProcessing(_ processing: Bool) {
        isProcessing = processing
    }

    /// Flash an error on the indicator for ~3 seconds, then auto-hide.
    /// Safe to call when the indicator is not currently visible.
    @MainActor
    func showError(_ message: String) {
        errorHideTask?.cancel()
        isProcessing = false
        audioLevel = 0
        errorMessage = message
        if isShowing {
            recreatePanel()
        } else {
            isShowing = true
            createPanel()
        }

        errorHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.errorDisplayDuration))
            if Task.isCancelled { return }
            await MainActor.run {
                guard let self else { return }
                self.errorMessage = nil
                self.hide()
            }
        }
    }

    // MARK: - Panel Management

    private func createPanel() {
        let screen = focusedScreen()
        let effectiveMode = mode.effective(on: screen)
        let frame = panelFrame(for: effectiveMode, on: screen)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = (effectiveMode == .floatingWindow)

        let contentView = StatusIndicatorContentView(manager: self, mode: effectiveMode)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        // Prevent the hosting view from driving window size changes
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func recreatePanel() {
        panel?.orderOut(nil)
        panel = nil
        createPanel()
    }

    private func panelFrame(for mode: StatusIndicatorMode, on screen: NSScreen) -> NSRect {
        let screenFrame = screen.visibleFrame
        let screenFullFrame = screen.frame

        switch mode {
        case .notch:
            if let leftArea = screen.auxiliaryTopLeftArea,
               let rightArea = screen.auxiliaryTopRightArea {
                let height = leftArea.height
                let notchLeftEdge = leftArea.origin.x + leftArea.width
                let notchRightEdge = rightArea.origin.x
                let baseWidth = (notchRightEdge - notchLeftEdge) + Self.notchSideExtension * 2
                let width = preferredPanelWidth(
                    defaultWidth: baseWidth,
                    fontSize: 11,
                    on: screen
                )
                let centerX = (notchLeftEdge + notchRightEdge) / 2
                let x = centeredOriginX(centerX: centerX, width: width, in: screenFullFrame)
                let y = screenFullFrame.maxY - height
                return NSRect(x: x, y: y, width: width, height: height)
            }

            // Fallback for screens without notch.
            let height: CGFloat = 32
            let width = preferredPanelWidth(defaultWidth: 200, fontSize: 11, on: screen)
            let x = centeredOriginX(centerX: screenFullFrame.midX, width: width, in: screenFullFrame)
            let y = screenFullFrame.maxY - height
            return NSRect(x: x, y: y, width: width, height: height)

        case .topCenter:
            let width = preferredPanelWidth(defaultWidth: 240, fontSize: 12, on: screen)
            let height: CGFloat = 36
            let x = centeredOriginX(centerX: screenFrame.midX, width: width, in: screenFrame)
            let y = screenFrame.maxY - height - 4
            return NSRect(x: x, y: y, width: width, height: height)

        case .floatingWindow:
            let width = preferredPanelWidth(defaultWidth: 320, fontSize: 13, on: screen)
            let height: CGFloat = 80
            let x = centeredOriginX(centerX: screenFrame.midX, width: width, in: screenFrame)
            let y = screenFrame.maxY - height - 60
            return NSRect(x: x, y: y, width: width, height: height)
        }
    }

    private func preferredPanelWidth(
        defaultWidth: CGFloat,
        fontSize: CGFloat,
        on screen: NSScreen
    ) -> CGFloat {
        guard let errorMessage else { return defaultWidth }

        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let textWidth = (errorMessage as NSString).size(withAttributes: [.font: font]).width
        // Allow generous room for the warning icon, SwiftUI HStack spacing,
        // and mode-specific padding. The screen edge is the only cap; normal
        // messages should never be shortened to an arbitrary panel maximum.
        let desiredWidth = ceil(textWidth) + 96
        let maximumWidth = max(defaultWidth, screen.visibleFrame.width - 24)
        return min(max(defaultWidth, desiredWidth), maximumWidth)
    }

    private func centeredOriginX(centerX: CGFloat, width: CGFloat, in frame: NSRect) -> CGFloat {
        let margin: CGFloat = 8
        return min(
            max(centerX - width / 2, frame.minX + margin),
            frame.maxX - width - margin
        )
    }


    /// Get the screen containing the currently focused window.
    private func focusedScreen() -> NSScreen {
        guard let mainScreen = NSScreen.main else {
            return NSScreen.screens.first ?? NSScreen()
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return mainScreen
        }

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == frontApp.processIdentifier,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: NSNumber]
            else { continue }

            let x = boundsDict["X"]?.doubleValue ?? 0
            let y = boundsDict["Y"]?.doubleValue ?? 0
            let w = boundsDict["Width"]?.doubleValue ?? 0
            let h = boundsDict["Height"]?.doubleValue ?? 0

            guard w > 0, h > 0 else { continue }

            let windowCenter = NSPoint(x: x + w / 2, y: y + h / 2)
            for screen in NSScreen.screens {
                // CGWindowList uses top-left origin; NSScreen uses bottom-left.
                // Convert the window center to NSScreen coordinates.
                let screenHeight = NSScreen.screens.first?.frame.height ?? mainScreen.frame.height
                let flippedCenter = NSPoint(x: windowCenter.x, y: screenHeight - windowCenter.y)
                if screen.frame.contains(flippedCenter) {
                    return screen
                }
            }
        }

        return mainScreen
    }
}
