import SwiftUI

struct EmptyStateView: View {
    var icon: String = "tray"
    var title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Color.text3)

            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.headingMedium)
                    .foregroundStyle(Color.text1)
                if let message {
                    Text(message)
                        .font(.bodySmall)
                        .foregroundStyle(Color.text2)
                        .multilineTextAlignment(.center)
                }
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
