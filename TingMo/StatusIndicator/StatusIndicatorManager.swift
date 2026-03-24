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

    /// How far (in points) the notch bar extends beyond each side of the physical notch.
    static let notchSideExtension: CGFloat = 34

    private(set) var isShowing = false
    private var panel: NSPanel?

    init() {
        let saved = UserDefaults.standard.string(forKey: "StatusIndicator.mode") ?? StatusIndicatorMode.notch.rawValue
        mode = StatusIndicatorMode(rawValue: saved) ?? .notch
    }

    func show() {
        guard !isShowing else { return }
        isShowing = true
        createPanel()
    }

    func hide() {
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

    private func panelFrame(for mode: StatusIndicatorMode, on screen: NSScreen) -> NSRect {
        let screenFrame = screen.visibleFrame
        let screenFullFrame = screen.frame

        switch mode {
        case .notch:
            let ext = Self.notchSideExtension

            if let leftArea = screen.auxiliaryTopLeftArea,
               let rightArea = screen.auxiliaryTopRightArea {
                let height = leftArea.height
                let notchLeftEdge = leftArea.origin.x + leftArea.width
                let notchRightEdge = rightArea.origin.x
                let x = notchLeftEdge - ext
                let totalWidth = (notchRightEdge - notchLeftEdge) + ext * 2
                let y = screenFullFrame.maxY - height
                return NSRect(x: x, y: y, width: totalWidth, height: height)
            }
            // Fallback for screens without notch
            let height: CGFloat = 32
            let width: CGFloat = 200
            let x = screenFullFrame.midX - width / 2
            let y = screenFullFrame.maxY - height
            return NSRect(x: x, y: y, width: width, height: height)

        case .topCenter:
            let width: CGFloat = 240
            let height: CGFloat = 36
            let x = screenFrame.midX - width / 2
            let y = screenFrame.maxY - height - 4
            return NSRect(x: x, y: y, width: width, height: height)

        case .floatingWindow:
            let width: CGFloat = 320
            let height: CGFloat = 80
            let x = screenFrame.midX - width / 2
            let y = screenFrame.maxY - height - 60
            return NSRect(x: x, y: y, width: width, height: height)
        }
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
