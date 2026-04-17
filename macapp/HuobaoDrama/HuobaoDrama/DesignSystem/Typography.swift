import SwiftUI

extension Font {
    static let displayLarge = Font.system(size: 32, weight: .bold)
    static let displayMedium = Font.system(size: 24, weight: .bold)
    static let displaySmall = Font.system(size: 20, weight: .semibold)

    static let headingLarge = Font.system(size: 18, weight: .semibold)
    static let headingMedium = Font.system(size: 16, weight: .semibold)
    static let headingSmall = Font.system(size: 14, weight: .semibold)

    static let bodyLarge = Font.system(size: 15, weight: .regular)
    static let bodyMedium = Font.system(size: 14, weight: .regular)
    static let bodySmall = Font.system(size: 13, weight: .regular)

    static let labelMedium = Font.system(size: 12, weight: .medium)
    static let labelSmall = Font.system(size: 11, weight: .medium)

    static let monoMedium = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 12, weight: .regular, design: .monospaced)
}
