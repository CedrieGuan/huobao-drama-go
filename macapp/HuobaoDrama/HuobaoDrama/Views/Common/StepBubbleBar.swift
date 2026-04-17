import SwiftUI

struct StepBubble: Identifiable {
    var id: Int
    var label: String
    var icon: String?
}

struct StepBubbleBar: View {
    var steps: [StepBubble]
    @Binding var currentStep: Int
    var onStepTap: ((Int) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                    HStack(spacing: 0) {
                        Button {
                            onStepTap?(step.id)
                        } label: {
                            VStack(spacing: Spacing.xs) {
                                ZStack {
                                    Circle()
                                        .fill(currentStep == step.id ? Color.accent : (currentStep > step.id ? Color.statusSuccess : Color.bg2))
                                        .frame(width: 28, height: 28)
                                    if currentStep > step.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                    } else {
                                        Text("\(idx + 1)")
                                            .font(.labelSmall)
                                            .foregroundStyle(currentStep == step.id ? .white : Color.text2)
                                    }
                                }
                                Text(step.label)
                                    .font(.labelSmall)
                                    .foregroundStyle(currentStep == step.id ? Color.accent : Color.text2)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                        .buttonStyle(.plain)

                        if idx < steps.count - 1 {
                            Rectangle()
                                .fill(currentStep > step.id ? Color.statusSuccess : Color.border0)
                                .frame(width: 24, height: 2)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
        }
    }
}
