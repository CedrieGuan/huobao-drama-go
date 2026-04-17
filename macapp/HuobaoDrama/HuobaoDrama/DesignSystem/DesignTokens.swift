import SwiftUI

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let section: CGFloat = 40
}

enum Radius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let full: CGFloat = 9999
}

enum IconSize {
    static let xs: CGFloat = 12
    static let sm: CGFloat = 16
    static let md: CGFloat = 20
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum Animation {
    static let fast = SwiftUI.Animation.easeInOut(duration: 0.15)
    static let normal = SwiftUI.Animation.easeInOut(duration: 0.25)
    static let slow = SwiftUI.Animation.easeInOut(duration: 0.4)
    static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
}
