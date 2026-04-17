import SwiftUI

struct LoadingOverlay: View {
    var message: String = "加载中..."

    var body: some View {
        ZStack {
            Color.bgOverlay
                .ignoresSafeArea()
            VStack(spacing: Spacing.lg) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)
                Text(message)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textInverse)
            }
            .padding(Spacing.xxl)
            .background(Color.text0.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }
}

struct InlineLoadingView: View {
    var message: String = "处理中..."

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.7)
            Text(message)
                .font(.bodySmall)
                .foregroundStyle(Color.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
