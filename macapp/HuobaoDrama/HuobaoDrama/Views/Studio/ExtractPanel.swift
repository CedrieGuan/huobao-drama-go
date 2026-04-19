import SwiftUI

// MARK: - ExtractPanel

/// Step 03 of the script pipeline: AI-extracted characters and scenes.
/// Shows an empty state, loading indicator, or character/scene results depending on state.
struct ExtractPanel: View {
    @ObservedObject var viewModel: StudioViewModel

    // Pulse animation state
    @State private var pulsePhase = false

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()
            contentArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: Spacing.md) {
            // Statistics
            if hasResults {
                Text("\(viewModel.characters.count) 角色")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text2)
                Text("\u{00B7}")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text3)
                Text("\(viewModel.scenes.count) 场景")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text2)
            }

            Spacer()

            // Error feedback
            if let error = viewModel.extractError {
                Text(error)
                    .font(.labelSmall)
                    .foregroundStyle(Color.statusError)
                    .lineLimit(1)
            }

            // Re-extract button (only when results exist)
            if hasResults && !viewModel.isExtracting {
                Button {
                    Task { await viewModel.runExtract() }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: IconSize.xs, weight: .medium))
                        Text("重新提取")
                            .font(.bodySmall.weight(.medium))
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgCard)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isExtracting {
            loadingView
        } else if hasResults {
            resultsView
        } else {
            emptyView
        }
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Visual
            Image(systemName: "person.2")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.text3)
                .frame(width: 64, height: 64)
                .background(Color.bg2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

            // Title
            Text("从剧本提取角色与场景")
                .font(.headingLarge)
                .foregroundStyle(Color.text1)

            // Description
            Text("AI 会自动分析剧本内容，识别出所有角色及其特征，并提取场景信息。")
                .font(.bodyMedium)
                .foregroundStyle(Color.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .lineSpacing(2)

            // Action button
            Button {
                Task { await viewModel.runExtract() }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: IconSize.xs, weight: .medium))
                    Text("开始提取")
                        .font(.bodySmall.weight(.medium))
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg1)
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .tint(Color.accent)

            Text("正在提取角色和场景...")
                .font(.bodyMedium)
                .foregroundStyle(Color.text2)

            // Animated dots
            HStack(spacing: Spacing.xs) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.accent.opacity(0.4))
                        .frame(width: 6, height: 6)
                        .scaleEffect(pulsePhase ? 1.4 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: pulsePhase
                        )
                }
            }
            .onAppear { pulsePhase = true }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg1)
    }

    // MARK: - Results View

    private var resultsView: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            // Left: Summary card
            summaryCard

            // Right: Characters + Scenes list
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    // Characters section
                    charactersSection

                    // Scenes section
                    scenesSection
                }
                .padding(Spacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.bg1)
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("角色与场景结果")
                .font(.headingSmall)
                .foregroundStyle(Color.text0)

            Divider()

            // Character count
            HStack(spacing: Spacing.sm) {
                Image(systemName: "person.fill")
                    .font(.system(size: IconSize.sm))
                    .foregroundStyle(Color.accent)
                Text("\(viewModel.characters.count)")
                    .font(.displayMedium)
                    .foregroundStyle(Color.text0)
                Text("个角色")
                    .font(.bodySmall)
                    .foregroundStyle(Color.text2)
            }

            // Scene count
            HStack(spacing: Spacing.sm) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: IconSize.sm))
                    .foregroundStyle(Color.accent)
                Text("\(viewModel.scenes.count)")
                    .font(.displayMedium)
                    .foregroundStyle(Color.text0)
                Text("个场景")
                    .font(.bodySmall)
                    .foregroundStyle(Color.text2)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 180)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .cardShadow()
    }

    // MARK: - Characters Section

    private var charactersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("角色")
                .font(.headingSmall)
                .foregroundStyle(Color.text0)

            if viewModel.characters.isEmpty {
                Text("暂无角色")
                    .font(.bodySmall)
                    .foregroundStyle(Color.text3)
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.lg)
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(viewModel.characters) { character in
                        characterRow(character)
                    }
                }
            }
        }
    }

    private func characterRow(_ character: Character) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            // Avatar: first letter of name
            Text(String(character.name.prefix(1)))
                .font(.bodyLarge.weight(.semibold))
                .foregroundStyle(Color.textInverse)
                .frame(width: 32, height: 32)
                .background(Color.accent)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(character.name)
                        .font(.bodyMedium.weight(.medium))
                        .foregroundStyle(Color.text0)

                    // Role tag
                    if let role = character.role, !role.isEmpty {
                        TagView(
                            text: role,
                            color: Color.accent,
                            bgColor: Color.accentLight,
                            size: .small
                        )
                    }
                }

                if let desc = character.description, !desc.isEmpty {
                    Text(desc)
                        .font(.bodySmall)
                        .foregroundStyle(Color.text2)
                        .lineLimit(2)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - Scenes Section

    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("场景")
                .font(.headingSmall)
                .foregroundStyle(Color.text0)

            if viewModel.scenes.isEmpty {
                Text("暂无场景")
                    .font(.bodySmall)
                    .foregroundStyle(Color.text3)
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.lg)
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(viewModel.scenes) { scene in
                        sceneRow(scene)
                    }
                }
            }
        }
    }

    private func sceneRow(_ scene: Scene) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            // Icon
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: IconSize.sm))
                .foregroundStyle(Color.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(scene.location)
                        .font(.bodyMedium.weight(.medium))
                        .foregroundStyle(Color.text0)

                    // Time tag
                    if !scene.time.isEmpty {
                        TagView(
                            text: scene.time,
                            color: Color.text2,
                            bgColor: Color.bg2,
                            size: .small
                        )
                    }
                }

                if !scene.prompt.isEmpty {
                    Text(scene.prompt)
                        .font(.bodySmall)
                        .foregroundStyle(Color.text2)
                        .lineLimit(2)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - Helpers

    /// Whether there are extraction results to display.
    private var hasResults: Bool {
        !viewModel.characters.isEmpty || !viewModel.scenes.isEmpty
    }
}
