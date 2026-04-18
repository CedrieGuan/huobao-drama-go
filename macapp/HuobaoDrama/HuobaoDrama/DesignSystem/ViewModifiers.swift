import SwiftUI

// MARK: - Card Background
struct CardBackground: ViewModifier {
    var padding: CGFloat = Spacing.lg
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .cardShadow()
    }
}

// MARK: - Section Header
struct SectionHeader: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headingSmall)
            .foregroundStyle(Color.text2)
            .textCase(.uppercase)
    }
}

// MARK: - Primary Button Style
struct PrimaryButtonStyle: ButtonStyle {
    var isDestructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyMedium.weight(.medium))
            .foregroundStyle(Color.textInverse)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(isDestructive ? Color.statusError : Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(Animation.fast, value: configuration.isPressed)
    }
}

// MARK: - Secondary Button Style
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyMedium.weight(.medium))
            .foregroundStyle(Color.text1)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(Color.bg2)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.border0, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(Animation.fast, value: configuration.isPressed)
    }
}

// MARK: - Ghost Button Style
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodySmall)
            .foregroundStyle(Color.accent)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(configuration.isPressed ? Color.accentLight : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
            .animation(Animation.fast, value: configuration.isPressed)
    }
}

// MARK: - Icon Button Style
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.text2)
            .padding(Spacing.xs)
            .background(configuration.isPressed ? Color.bg2 : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
            .animation(Animation.fast, value: configuration.isPressed)
    }
}

// MARK: - Text Field Style
struct AppTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.bodyMedium)
            .foregroundStyle(Color.text0)
            .padding(Spacing.sm)
            .background(Color.bg1)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.border0, lineWidth: 1))
    }
}

// MARK: - View Extensions
extension View {
    func cardStyle(padding: CGFloat = Spacing.lg) -> some View {
        modifier(CardBackground(padding: padding))
    }

    func sectionHeader() -> some View {
        modifier(SectionHeader())
    }

    func shimmer(isActive: Bool) -> some View {
        overlay(
            Group {
                if isActive {
                    ShimmerView()
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }
}

struct ShimmerView: View {
    @State private var phase: CGFloat = -1
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                gradient: Gradient(colors: shimmerColors),
                startPoint: .init(x: phase, y: 0),
                endPoint: .init(x: phase + 1, y: 0)
            )
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
    
    private var shimmerColors: [Color] {
        colorScheme == .dark
            ? [.clear, Color.white.opacity(0.15), .clear]
            : [.clear, Color.white.opacity(0.4), .clear]
    }
}
