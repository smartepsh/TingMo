import SwiftUI

/// Animated waveform that responds to audio input levels.
struct WaveformView: View {
    let audioLevel: Float
    let barCount: Int
    let isProcessing: Bool

    init(audioLevel: Float = 0, barCount: Int = 5, isProcessing: Bool = false) {
        self.audioLevel = audioLevel
        self.barCount = barCount
        self.isProcessing = isProcessing
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate

            if isProcessing {
                processingIndicator(phase: phase)
            } else {
                waveformBars(phase: phase)
            }
        }
    }

    private func waveformBars(phase: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white)
                    .frame(width: 3, height: barHeight(index: index, phase: phase))
            }
        }
    }

    private func processingIndicator(phase: Double) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
                    .opacity(processingDotOpacity(index: index, phase: phase))
            }
        }
    }

    private func barHeight(index: Int, phase: Double) -> CGFloat {
        let minHeight: CGFloat = 4
        let maxHeight: CGFloat = 20
        let offset = Double(index) * (.pi / 2.5)
        let wave = sin(phase * 4.0 + offset)
        let level = CGFloat(max(0.05, audioLevel))
        let height = minHeight + (maxHeight - minHeight) * level * CGFloat(0.5 + 0.5 * wave)
        return max(minHeight, height)
    }

    private func processingDotOpacity(index: Int, phase: Double) -> Double {
        let offset = Double(index) * (.pi * 2 / 3)
        return 0.3 + 0.7 * max(0, sin(phase * 3.0 + offset))
    }
}
