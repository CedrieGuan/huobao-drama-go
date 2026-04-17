import SwiftUI

struct TagView: View {
    var text: String
    var color: Color = Color.accent
    var bgColor: Color = Color.accentLight
    var icon: String? = nil
    var size: TagSize = .medium

    enum TagSize { case small, medium }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(size == .small ? .system(size: 9) : .labelSmall)
            }
            Text(text)
                .font(size == .small ? .labelSmall : .labelMedium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, size == .small ? Spacing.xs : Spacing.sm)
        .padding(.vertical, size == .small ? 2 : Spacing.xs)
        .background(bgColor)
        .clipShape(Capsule())
    }
}

extension TagView {
    static func status(_ status: String) -> TagView {
        let (text, color, bg): (String, Color, Color) = {
            switch status {
            case "completed": return ("已完成", .statusSuccess, .statusSuccessLight)
            case "in_production": return ("制作中", .statusInfo, .statusInfoLight)
            case "draft": return ("草稿", .text2, .bg2)
            case "failed": return ("失败", .statusError, .statusErrorLight)
            default: return (status, .text2, .bg2)
            }
        }()
        return TagView(text: text, color: color, bgColor: bg)
    }
}
