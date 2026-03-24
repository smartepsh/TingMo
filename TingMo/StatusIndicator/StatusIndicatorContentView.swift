import SwiftUI

/// A shape that looks like the native notch expanded horizontally.
/// Top edge is flush with the screen top. Bottom-left and bottom-right corners
/// use the same radius as the physical notch, so it appears the notch simply grew wider.
struct NotchBarShape: Shape {
    /// Corner radius matching the physical notch's bottom corners (~10pt on most MacBooks).
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(cornerRadius, rect.height, rect.width / 2)

        // Start at top-left (flush with screen top, no rounding on top edge)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Top edge
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Right edge down to bottom-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        // Bottom-right rounded corner
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        // Bottom-left rounded corner
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        // Left edge back to top
        path.closeSubpath()

        return path
    }
}

struct StatusIndicatorContentView: View {
    let manager: StatusIndicatorManager
    let mode: StatusIndicatorMode

    var body: some View {
        switch mode {
        case .notch:
            notchView
        case .topCenter:
            topCenterView
        case .floatingWindow:
            floatingWindowView
        }
    }

    // MARK: - Notch Mode

    private var notchView: some View {
        ZStack {
            // Black bar that visually extends the notch
            NotchBarShape(cornerRadius: 10)
                .fill(.black)

            // Content: recording dot on the left side, waveform on the right side
            HStack {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: .red.opacity(0.5), radius: 4, x: 0, y: 0)

                Spacer()

                WaveformView(audioLevel: manager.audioLevel, barCount: 4, isProcessing: manager.isProcessing)
                    .frame(width: 28)
            }
            .padding(.horizontal, 10)
        }
    }

    // MARK: - Top Center Mode

    private var topCenterView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)

            WaveformView(audioLevel: manager.audioLevel, barCount: 7, isProcessing: manager.isProcessing)
                .frame(height: 22)

            if !manager.previewText.isEmpty {
                Text(manager.previewText)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.black.opacity(0.8))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
        )
    }

    // MARK: - Floating Window Mode

    private var floatingWindowView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)

                Text(manager.isProcessing ? String(localized: "Processing...") : String(localized: "Recording"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)

                Spacer()

                WaveformView(audioLevel: manager.audioLevel, barCount: 9, isProcessing: manager.isProcessing)
                    .frame(height: 24)
            }

            if !manager.previewText.isEmpty {
                Text(manager.previewText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.7))
        )
    }
}
