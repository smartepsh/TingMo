import SwiftUI

struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "mic.and.signal.meter")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Welcome to TingMo")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your intelligent dictation assistant")
                .font(.title3)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
