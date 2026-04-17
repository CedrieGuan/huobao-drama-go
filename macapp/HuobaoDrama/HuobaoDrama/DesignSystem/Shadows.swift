import SwiftUI

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension ShadowStyle {
    static let card = ShadowStyle(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    static let elevated = ShadowStyle(color: .black.opacity(0.10), radius: 16, x: 0, y: 4)
    static let modal = ShadowStyle(color: .black.opacity(0.16), radius: 24, x: 0, y: 8)
    static let button = ShadowStyle(color: Color.accent.opacity(0.3), radius: 8, x: 0, y: 4)
}

extension View {
    func cardShadow() -> some View {
        shadow(color: ShadowStyle.card.color, radius: ShadowStyle.card.radius, x: ShadowStyle.card.x, y: ShadowStyle.card.y)
    }
    func elevatedShadow() -> some View {
        shadow(color: ShadowStyle.elevated.color, radius: ShadowStyle.elevated.radius, x: ShadowStyle.elevated.x, y: ShadowStyle.elevated.y)
    }
    func modalShadow() -> some View {
        shadow(color: ShadowStyle.modal.color, radius: ShadowStyle.modal.radius, x: ShadowStyle.modal.x, y: ShadowStyle.modal.y)
    }
}
