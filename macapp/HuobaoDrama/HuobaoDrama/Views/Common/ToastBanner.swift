import SwiftUI

/// A lightweight toast banner that auto-dismisses after a delay.
/// Used to surface success/error messages from async operations.
struct ToastBanner: View {
    let toast: AppToast
    let onDismiss: () -> Void

    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: toast.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(toast.kind == .success ? Color.statusSuccess : Color.statusError)

            Text(toast.message)
                .font(.bodyMedium)
                .foregroundStyle(Color.text0)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.text2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(
            toast.kind == .success ? Color.statusSuccess.opacity(0.3) : Color.statusError.opacity(0.3),
            lineWidth: 1
        ))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        .padding(.horizontal, Spacing.xxxl)
        .onAppear {
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                dismiss()
            }
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    private func dismiss() {
        dismissTask?.cancel()
        onDismiss()
    }
}
