import SwiftUI

// MARK: - Studio Step

enum StudioStep: Int, CaseIterable {
    case rawContent = 0
    case rewrite = 1
    case extract = 2
    case voiceAssign = 3
    case storyboard = 4

    var title: String {
        switch self {
        case .rawContent:   return "原始内容"
        case .rewrite:      return "AI改写"
        case .extract:      return "提取角色场景"
        case .voiceAssign:  return "分配音色"
        case .storyboard:   return "分镜列表"
        }
    }

    var icon: String {
        switch self {
        case .rawContent:   return "doc.text"
        case .rewrite:      return "sparkles"
        case .extract:      return "person.2"
        case .voiceAssign:  return "waveform"
        case .storyboard:   return "film"
        }
    }

    /// Section grouping for the sidebar.
    var section: String {
        switch self {
        case .rawContent, .rewrite, .extract, .voiceAssign, .storyboard:
            return "剧本"
        }
    }
}

// MARK: - Step Section

private struct StepSection: Identifiable {
    let id: String
    let label: String
    let steps: [StudioStep]
}

/// Precomputed sections for sidebar grouping.
private let sidebarSections: [StepSection] = [
    StepSection(id: "script", label: "剧本", steps: StudioStep.allCases)
]

// MARK: - StudioPage

struct StudioPage: View {
    let episodeId: Int
    let dramaId: Int

    @State private var viewModel: StudioViewModel
    @Environment(Router.self) private var router

    init(episodeId: Int, dramaId: Int) {
        self.episodeId = episodeId
        self.dramaId = dramaId
        self._viewModel = State(initialValue: StudioViewModel(episodeId: episodeId, dramaId: dramaId))
    }

    /// Convenience accessor for the current step from the ViewModel.
    private var currentStep: StudioStep {
        viewModel.currentStep
    }

    var body: some View {
        VStack(spacing: 0) {
            topbar
            HStack(spacing: 0) {
                sidebar
                Divider()
                mainContent
            }
        }
        .background(Color.bg1)
        .task { await viewModel.load() }
    }

    // MARK: - Topbar

    private var topbar: some View {
        HStack(spacing: Spacing.md) {
            // -- Back button --
            Button {
                router.pop()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: IconSize.sm, weight: .medium))
                    Text("返回")
                        .font(.bodySmall.weight(.medium))
                }
                .foregroundStyle(Color.text2)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.border0, lineWidth: 1))
            }
            .buttonStyle(.plain)

            // -- Identity: title + episode chip + meta --
            HStack(spacing: Spacing.sm) {
                if let drama = viewModel.drama {
                    Text(drama.title)
                        .font(.headingMedium)
                        .foregroundStyle(Color.text0)
                        .lineLimit(1)
                } else {
                    Text("加载中...")
                        .font(.headingMedium)
                        .foregroundStyle(Color.text3)
                }

                if let episode = viewModel.episode {
                    Text("第 \(episode.episodeNumber) 集")
                        .font(.labelSmall)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Color.accentLight)
                        .foregroundStyle(Color.accent)
                        .clipShape(Capsule())
                }

                // Meta pills: current step label + progress count
                if !viewModel.stepDescriptions.isEmpty {
                    Text(viewModel.stepDescriptions.last ?? "")
                        .font(.labelSmall)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Color.statusInfoLight)
                        .foregroundStyle(Color.statusInfo)
                        .clipShape(Capsule())
                }

                Text(viewModel.progressLabel)
                    .font(.labelSmall)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 2)
                    .background(Color.bg2)
                    .foregroundStyle(Color.text2)
                    .clipShape(Capsule())
            }

            Spacer()

            // -- Progress bar (compact) --
            progressBar
                .padding(.trailing, Spacing.sm)

            // -- Refresh button --
            Button {
                Task { await viewModel.reload() }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: IconSize.xs, weight: .medium))
                    Text("刷新")
                        .font(.bodySmall.weight(.medium))
                }
                .foregroundStyle(Color.text2)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.border0, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
        .background(Color.bgCard)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(alignment: .trailing, spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: Radius.full)
                        .fill(Color.bg3)
                        .frame(height: 4)
                    // Fill
                    RoundedRectangle(cornerRadius: Radius.full)
                        .fill(viewModel.progressFraction >= 1.0 ? Color.statusSuccess : Color.accent)
                        .frame(width: max(0, geo.size.width * viewModel.progressFraction), height: 4)
                        .animation(Animation.normal, value: viewModel.progressFraction)
                }
            }
            .frame(width: 80, height: 4)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Scrollable pipeline area
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ForEach(sidebarSections) { section in
                        sectionView(section)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.xl)
                .padding(.bottom, Spacing.md)
            }

            Spacer(minLength: 0)

            // Bottom progress bar
            sidebarBottom
        }
        .frame(width: 220)
        .background(Color.bgCard)
    }

    // MARK: - Section

    private func sectionView(_ section: StepSection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Section label
            Text(section.label)
                .font(.labelSmall.weight(.bold))
                .foregroundStyle(Color.text3)
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, Spacing.xs)

            // Step items with connector lines
            VStack(spacing: 0) {
                ForEach(Array(section.steps.enumerated()), id: \.element.rawValue) { index, step in
                    stepRow(step, isLast: index == section.steps.count - 1)
                }
            }
        }
    }

    // MARK: - Step Row

    private func stepRow(_ step: StudioStep, isLast: Bool) -> some View {
        let isActive = step == currentStep
        let stepStatus = viewModel.status(for: step)

        return Button {
            viewModel.currentStep = step
        } label: {
            HStack(spacing: Spacing.md) {
                // Icon circle with status styling
                ZStack {
                    Circle()
                        .fill(iconBackground(stepStatus: stepStatus, isActive: isActive))
                        .frame(width: 26, height: 26)
                    Circle()
                        .stroke(iconBorder(stepStatus: stepStatus, isActive: isActive), lineWidth: 1)
                        .frame(width: 26, height: 26)

                    if stepStatus == .completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.textInverse)
                    } else if isActive {
                        Image(systemName: step.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.textInverse)
                    } else {
                        Image(systemName: step.icon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.text3)
                    }
                }
                .zIndex(1)

                // Step title
                Text(step.title)
                    .font(.bodyMedium.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(stepForeground(stepStatus: stepStatus, isActive: isActive))
                    .lineLimit(1)

                Spacer()

                // Status badge for in-progress
                if stepStatus == .inProgress && !isActive {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(isActive ? Color.accentLight : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            // Connector line between steps
            if !isLast {
                Rectangle()
                    .fill(Color.border0)
                    .frame(width: 1)
                    .offset(y: -4)
                    .padding(.leading, 21) // center under the icon (16 sm + 5 offset)
            }
        }
    }

    // MARK: - Step Style Helpers

    private func iconBackground(stepStatus: StepStatus, isActive: Bool) -> Color {
        if stepStatus == .completed { return Color.statusSuccess }
        if isActive { return Color.accent }
        return Color.bg1
    }

    private func iconBorder(stepStatus: StepStatus, isActive: Bool) -> Color {
        if stepStatus == .completed { return Color.statusSuccess }
        if isActive { return Color.accent }
        return Color.border0
    }

    private func stepForeground(stepStatus: StepStatus, isActive: Bool) -> Color {
        if stepStatus == .completed && !isActive { return Color.statusSuccess }
        if isActive { return Color.text0 }
        return Color.text1
    }

    // MARK: - Sidebar Bottom

    private var sidebarBottom: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Progress header
            HStack {
                Text("制作进度")
                    .font(.labelSmall)
                    .foregroundStyle(Color.text3)
                Spacer()
                Text("\(viewModel.completedStepCount)/\(viewModel.totalSteps)")
                    .font(.labelSmall)
                    .foregroundStyle(Color.text2)
                    .monospacedDigit()
            }

            // Progress track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Radius.full)
                        .fill(Color.bg3)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: Radius.full)
                        .fill(viewModel.progressFraction >= 1.0 ? Color.statusSuccess : Color.accent)
                        .frame(width: max(0, geo.size.width * viewModel.progressFraction), height: 4)
                        .animation(Animation.normal, value: viewModel.progressFraction)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.lg)
        .background(
            VStack(spacing: 0) {
                Divider()
                Color.bgCard
            }
        )
    }

    // MARK: - Main Content

    private var mainContent: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.error != nil {
                errorView
            } else {
                ScriptPanel(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text("加载中...")
                .font(.bodyMedium)
                .foregroundStyle(Color.text3)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: IconSize.xl))
                .foregroundStyle(Color.statusWarning)
            Text(viewModel.error ?? "未知错误")
                .font(.bodyMedium)
                .foregroundStyle(Color.text2)
            Button("重试") {
                Task { await viewModel.reload() }
            }
            .buttonStyle(SecondaryButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xxxl)
    }
}
