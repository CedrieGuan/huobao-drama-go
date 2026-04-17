import SwiftUI

struct StatusDot: View {
    var status: String
    var size: CGFloat = 8

    var color: Color {
        switch status {
        case "completed", "done": return .statusSuccess
        case "failed": return .statusError
        case "processing", "in_production", "partial": return .statusWarning
        case "pending", "draft": return .text3
        default: return .text3
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}
