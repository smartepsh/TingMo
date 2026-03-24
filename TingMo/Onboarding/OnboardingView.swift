import SwiftUI

struct OnboardingView: View {
    let permissionManager: PermissionManager

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var currentStepIndex = 0

    private let steps = OnboardingStep.allCases

    private var currentStep: OnboardingStep {
        steps[currentStepIndex]
    }

    private var isFirstStep: Bool {
        currentStepIndex == 0
    }

    private var isLastStep: Bool {
        currentStepIndex == steps.count - 1
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 6) {
                ForEach(steps) { step in
                    Circle()
                        .fill(step.id <= currentStep.id ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)

            // Step content
            Group {
                switch currentStep {
                case .welcome:
                    WelcomeStepView()
                case .microphone, .speechRecognition, .accessibility, .screenRecording:
                    if let type = currentStep.permissionType {
                        PermissionStepView(type: type, permissionManager: permissionManager)
                    }
                case .engineDownload, .hotkeySetup:
                    PlaceholderStepView(step: currentStep)
                case .completion:
                    CompletionStepView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation buttons
            HStack {
                if !isFirstStep && !isLastStep {
                    Button(String(localized: "Back")) {
                        withAnimation { currentStepIndex -= 1 }
                    }
                }

                Spacer()

                if !isLastStep {
                    Button(String(localized: "Skip")) {
                        completeOnboarding()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                if isLastStep {
                    Button(String(localized: "Get Started")) {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(String(localized: "Next")) {
                        withAnimation { currentStepIndex += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 20)
        }
        .frame(width: 600, height: 450)
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        dismissWindow(id: "onboarding-window")
    }
}
