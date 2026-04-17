import SwiftUI

extension Color {
    // Backgrounds
    static let bg0 = Color(hex: "#FFFFFF")
    static let bg1 = Color(hex: "#F8F9FC")
    static let bg2 = Color(hex: "#F0F2F7")
    static let bg3 = Color(hex: "#E8EBF2")
    static let bgCard = Color(hex: "#FFFFFF")
    static let bgOverlay = Color.black.opacity(0.4)

    // Text
    static let text0 = Color(hex: "#182132")
    static let text1 = Color(hex: "#374357")
    static let text2 = Color(hex: "#6B7A96")
    static let text3 = Color(hex: "#9AA3B8")
    static let textDisabled = Color(hex: "#C4CAD9")
    static let textInverse = Color(hex: "#FFFFFF")

    // Accent / Brand
    static let accent = Color(hex: "#4C7DFF")
    static let accentHover = Color(hex: "#3A6AEF")
    static let accentLight = Color(hex: "#EBF0FF")

    // Borders
    static let border0 = Color(hex: "#E2E6F0")
    static let border1 = Color(hex: "#CDD3E3")

    // Status
    static let statusSuccess = Color(hex: "#22C55E")
    static let statusSuccessLight = Color(hex: "#DCFCE7")
    static let statusError = Color(hex: "#EF4444")
    static let statusErrorLight = Color(hex: "#FEE2E2")
    static let statusWarning = Color(hex: "#F59E0B")
    static let statusWarningLight = Color(hex: "#FEF3C7")
    static let statusInfo = Color(hex: "#3B82F6")
    static let statusInfoLight = Color(hex: "#DBEAFE")

    // Gradients
    static let gradientStart = Color(hex: "#667EEA")
    static let gradientEnd = Color(hex: "#764BA2")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (1, 1, 0)
        }
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}
