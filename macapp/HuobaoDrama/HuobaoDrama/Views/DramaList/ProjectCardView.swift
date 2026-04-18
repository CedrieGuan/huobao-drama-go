import SwiftUI

struct ProjectCardView: View {
    let drama: Drama
    var onDelete: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            filmStrip
            cardBody
            cardFooter
        }
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(isHovered ? Color.accent : Color.clear, lineWidth: 1)
        )
        .shadow(
            color: isHovered ? .accent.opacity(0.15) : .black.opacity(0.06),
            radius: isHovered ? 12 : 8, x: 0, y: isHovered ? 4 : 2
        )
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(Animation.normal, value: isHovered)
        .onTapGesture { onTap?() }
        .onHover { hovering in isHovered = hovering }
    }

    // MARK: - Film Strip

    private var filmStrip: some View {
        HStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(isHovered && (i == 1 || i == 3) ? Color.accent : Color.bg3)
                    .frame(width: 10, height: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.lg)
        .background(Color.bg2)
    }

    // MARK: - Card Body

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header: episode count + delete
            HStack {
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(Color.accent)
                        .frame(width: 6, height: 6)
                    Text("\(drama.episodes.count) 集")
                        .font(.labelSmall)
                        .foregroundStyle(Color.text3)
                }
                Spacer()
                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: IconSize.xs))
                            .foregroundStyle(Color.text3)
                    }
                    .buttonStyle(IconButtonStyle())
                    .opacity(isHovered ? 1 : 0)
                    .animation(Animation.fast, value: isHovered)
                }
            }

            // Title
            Text(drama.title)
                .font(.headingMedium)
                .foregroundStyle(Color.text0)
                .lineLimit(2)

            // Meta: style + chars + scenes
            HStack(spacing: Spacing.sm) {
                if let style = drama.style, !style.isEmpty {
                    Text(style)
                        .font(.labelSmall)
                        .foregroundStyle(Color.accent)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Color.accentLight)
                        .clipShape(Capsule())
                }
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "person")
                        .font(.system(size: 9))
                    Text("\(drama.characters.count)")
                }
                .font(.labelSmall)
                .foregroundStyle(Color.text3)

                HStack(spacing: Spacing.xs) {
                    Image(systemName: "rectangle")
                        .font(.system(size: 9))
                    Text("\(drama.scenes.count)")
                }
                .font(.labelSmall)
                .foregroundStyle(Color.text3)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.md)
    }

    // MARK: - Footer

    private var cardFooter: some View {
        HStack(spacing: Spacing.sm) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 99)
                        .fill(Color.bg3)
                    RoundedRectangle(cornerRadius: 99)
                        .fill(
                            LinearGradient(
                                colors: [.gradientStart, .gradientEnd],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * drama.progress)
                }
            }
            .frame(height: 3)

            // Date
            Text(drama.updatedAt.relativeString)
                .font(.labelSmall)
                .foregroundStyle(Color.text3)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Color.bgCard)
    }
}

// MARK: - Date Formatting

extension String {
    var relativeString: String {
        guard let date = ISO8601DateFormatter().date(from: self) else {
            return self
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
