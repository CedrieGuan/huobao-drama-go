import SwiftUI

struct CardView<Content: View>: View {
    var padding: CGFloat = Spacing.lg
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .cardShadow()
    }
}

struct SelectableCardView<Content: View>: View {
    var isSelected: Bool = false
    var padding: CGFloat = Spacing.lg
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(isSelected ? Color.accentLight : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(isSelected ? Color.accent : Color.border0, lineWidth: isSelected ? 2 : 1)
            )
            .cardShadow()
    }
}
