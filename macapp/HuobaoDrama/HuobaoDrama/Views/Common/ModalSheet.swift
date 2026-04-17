import SwiftUI

struct ModalSheet<Content: View>: View {
    var title: String
    var subtitle: String?
    @Binding var isPresented: Bool
    var maxWidth: CGFloat = 520
    var onConfirm: (() -> Void)?
    var confirmTitle: String = "确定"
    var confirmDisabled: Bool = false
    var isLoading: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headingMedium)
                        .foregroundStyle(Color.text0)
                    if let subtitle {
                        Text(subtitle)
                            .font(.bodySmall)
                            .foregroundStyle(Color.text2)
                    }
                }
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.text2)
                        .padding(Spacing.xs)
                        .background(Color.bg2)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.lg)

            Divider()

            // Body
            ScrollView {
                content()
                    .padding(Spacing.lg)
            }

            // Footer
            if let onConfirm {
                Divider()
                HStack(spacing: Spacing.sm) {
                    Spacer()
                    Button("取消") { isPresented = false }
                        .buttonStyle(SecondaryButtonStyle())
                    Button(confirmTitle) {
                        onConfirm()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(confirmDisabled || isLoading)
                }
                .padding(Spacing.lg)
            }
        }
        .frame(maxWidth: maxWidth)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .modalShadow()
        .onKeyPress(.escape) { isPresented = false; return .handled }
    }
}

extension View {
    func appSheet<Content: View>(
        isPresented: Binding<Bool>,
        title: String,
        subtitle: String? = nil,
        maxWidth: CGFloat = 520,
        onConfirm: (() -> Void)? = nil,
        confirmTitle: String = "确定",
        confirmDisabled: Bool = false,
        isLoading: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.overlay {
            if isPresented.wrappedValue {
                ZStack {
                    Color.bgOverlay.ignoresSafeArea()
                        .onTapGesture { isPresented.wrappedValue = false }
                    ModalSheet(
                        title: title,
                        subtitle: subtitle,
                        isPresented: isPresented,
                        maxWidth: maxWidth,
                        onConfirm: onConfirm,
                        confirmTitle: confirmTitle,
                        confirmDisabled: confirmDisabled,
                        isLoading: isLoading,
                        content: content
                    )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(999)
            }
        }
        .animation(Animation.normal, value: isPresented.wrappedValue)
    }
}
