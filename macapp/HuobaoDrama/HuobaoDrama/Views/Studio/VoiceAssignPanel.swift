import SwiftUI

// MARK: - VoiceAssignPanel

/// Step 04 of the script pipeline: assign voice profiles to characters.
/// Shows an empty state, loading indicator, or character voice assignment cards.
struct VoiceAssignPanel: View {
    @ObservedObject var viewModel: StudioViewModel

    /// Local voice selection state keyed by character id.
    @State private var selectedVoices: [Int: String] = [:]

    // Pulse animation state
    @State private var pulsePhase = false

    /// Whether audio is currently playing for a given character id.
    @State private var playingCharacterId: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()
            contentArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.loadVoiceProfiles()
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: Spacing.md) {
            // Statistics
            if hasResults {
                let assignedCount = assignedCount
                Text("已分配 \(assignedCount)/\(viewModel.characters.count)")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text2)
            }

            Spacer()

            // Error feedback
            if let error = viewModel.voiceAssignError {
                Text(error)
                    .font(.labelSmall)
                    .foregroundStyle(Color.statusError)
                    .lineLimit(1)
            }

            // Re-assign button (only when results exist)
            if hasResults && !viewModel.isAssigningVoices {
                Button {
                    Task { await viewModel.runVoiceAssignment() }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: IconSize.xs, weight: .medium))
                        Text("重新分配")
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
        if viewModel.isAssigningVoices {
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
            Image(systemName: "waveform")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.text3)
                .frame(width: 64, height: 64)
                .background(Color.bg2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

            // Title
            Text("为角色分配合适的音色")
                .font(.headingLarge)
                .foregroundStyle(Color.text1)

            // Description
            Text("AI 将根据角色特征自动匹配最合适的朗读音色，也可以手动调整。")
                .font(.bodyMedium)
                .foregroundStyle(Color.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .lineSpacing(2)

            // Action button
            Button {
                Task { await viewModel.runVoiceAssignment() }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: IconSize.xs, weight: .medium))
                    Text("AI 自动分配")
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

            Text("正在分配音色...")
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
            // Left: Statistics sidebar
            statisticsSidebar

            // Right: Character cards grid
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: Spacing.lg
                ) {
                    ForEach(viewModel.characters) { character in
                        voiceAssignCard(character)
                    }
                }
                .padding(Spacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.bg1)
    }

    // MARK: - Statistics Sidebar

    private var statisticsSidebar: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("声音分配")
                .font(.headingSmall)
                .foregroundStyle(Color.text0)

            Divider()

            // Assignment progress
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("分配进度")
                    .font(.labelSmall)
                    .foregroundStyle(Color.text3)

                HStack(spacing: Spacing.sm) {
                    Text("\(assignedCount)")
                        .font(.displayMedium)
                        .foregroundStyle(Color.accent)
                    Text("/ \(viewModel.characters.count)")
                        .font(.bodySmall)
                        .foregroundStyle(Color.text3)
                }
            }

            // Voice library info
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("音色库")
                    .font(.labelSmall)
                    .foregroundStyle(Color.text3)

                if viewModel.isLoadingVoices {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text("加载中...")
                            .font(.bodySmall)
                            .foregroundStyle(Color.text2)
                    }
                } else {
                    HStack(spacing: Spacing.sm) {
                        Text("\(viewModel.voiceProfiles.count)")
                            .font(.displayMedium)
                            .foregroundStyle(Color.text0)
                        Text("个音色")
                            .font(.bodySmall)
                            .foregroundStyle(Color.text2)
                    }
                }
            }

            // Trial listen count
            if let sampleCount = sampleFileCount, sampleCount > 0 {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("试听文件")
                        .font(.labelSmall)
                        .foregroundStyle(Color.text3)
                    HStack(spacing: Spacing.sm) {
                        Text("\(sampleCount)")
                            .font(.displayMedium)
                            .foregroundStyle(Color.text0)
                        Text("个")
                            .font(.bodySmall)
                            .foregroundStyle(Color.text2)
                    }
                }
            }
        }
        .padding(Spacing.xl)
        .frame(width: 180)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .cardShadow()
    }

    // MARK: - Voice Assignment Card

    private func voiceAssignCard(_ character: Character) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Character info header
                HStack(spacing: Spacing.md) {
                    // Avatar
                    Text(String(character.name.prefix(1)))
                        .font(.bodyLarge.weight(.semibold))
                        .foregroundStyle(Color.textInverse)
                        .frame(width: 32, height: 32)
                        .background(Color.accent)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(character.name)
                            .font(.bodyMedium.weight(.medium))
                            .foregroundStyle(Color.text0)

                        if let role = character.role, !role.isEmpty {
                            TagView(
                                text: role,
                                color: Color.accent,
                                bgColor: Color.accentLight,
                                size: .small
                            )
                        }
                    }

                    Spacer()
                }

                // Description
                if let desc = character.description, !desc.isEmpty {
                    Text(desc)
                        .font(.bodySmall)
                        .foregroundStyle(Color.text2)
                        .lineLimit(2)
                }

                Divider()

                // Voice picker
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("音色")
                        .font(.labelSmall)
                        .foregroundStyle(Color.text3)

                    SearchablePicker(
                        placeholder: "选择音色...",
                        options: voicePickerOptions,
                        selectedValue: Binding(
                            get: { selectedVoices[character.id] ?? character.voiceStyle },
                            set: { newValue in
                                selectedVoices[character.id] = newValue
                                Task {
                                    await viewModel.updateCharacterVoice(
                                        characterId: character.id,
                                        voiceStyle: newValue ?? ""
                                    )
                                }
                            }
                        )
                    )
                }

                // Assigned voice info
                let currentVoice = selectedVoices[character.id] ?? character.voiceStyle
                if let voice = currentVoice,
                   let profile = viewModel.voiceProfiles.first(where: { $0.voiceId == voice || $0.displayName == voice }) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(profile.voiceName)
                            .font(.bodySmall.weight(.medium))
                            .foregroundStyle(Color.text1)
                        if !profile.description.isEmpty {
                            Text(profile.description.joined(separator: ", "))
                                .font(.labelSmall)
                                .foregroundStyle(Color.text3)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// Whether there are characters with extraction results to display.
    private var hasResults: Bool {
        !viewModel.characters.isEmpty
    }

    /// Number of characters with an assigned voice style.
    private var assignedCount: Int {
        viewModel.characters.filter { char in
            let voice = selectedVoices[char.id] ?? char.voiceStyle
            return voice != nil && !voice!.isEmpty
        }.count
    }

    /// Number of characters that have a voice sample URL.
    private var sampleFileCount: Int? {
        let count = viewModel.characters.filter { $0.voiceSampleUrl != nil && !$0.voiceSampleUrl!.isEmpty }.count
        return count > 0 ? count : nil
    }

    /// Picker options generated from voice profiles.
    private var voicePickerOptions: [PickerOption] {
        viewModel.voiceProfiles.map { profile in
            PickerOption(
                id: "\(profile.id)",
                label: profile.displayName,
                value: profile.voiceId
            )
        }
    }
}
