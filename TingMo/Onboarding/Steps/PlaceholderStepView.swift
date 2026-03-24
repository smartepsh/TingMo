import SwiftUI

struct PlaceholderStepView: View {
    let step: OnboardingStep

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: step.placeholderIcon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(step.placeholderTitle)
                .font(.title)
                .fontWeight(.bold)

            Text("Will be configured in a future update")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
