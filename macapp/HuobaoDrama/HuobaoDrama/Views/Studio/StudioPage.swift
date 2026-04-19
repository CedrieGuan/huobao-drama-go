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

// MARK: - StudioPanel 顶级面板枚举（E9）

/// 顶级导航面板：剧本 / 制作 / 导出。
enum StudioPanel: String, CaseIterable {
    case script = "剧本"
    case production = "制作"
    case exportPanel = "导出"

    /// 面板对应的 SF Symbol 图标。
    var icon: String {
        switch self {
        case .script:      return "doc.text"
        case .production:  return "hammer"
        case .exportPanel: return "square.and.arrow.up"
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

    /// 当前激活的顶级面板。
    @State private var activePanel: StudioPanel = .script

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
            panelTabs
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

    // MARK: - 面板切换标签

    /// 在 topbar 下方显示的三面板切换标签，类似 segmented control。
    private var panelTabs: some View {
        HStack(spacing: 0) {
            ForEach(StudioPanel.allCases, id: \.self) { panel in
                panelTabButton(panel)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.xs)
        .background(Color.bgCard)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    /// 单个面板切换按钮。
    private func panelTabButton(_ panel: StudioPanel) -> some View {
        let isActive = activePanel == panel

        return Button {
            withAnimation(Animation.normal) {
                activePanel = panel
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: panel.icon)
                    .font(.system(size: IconSize.sm, weight: isActive ? .semibold : .medium))
                Text(panel.rawValue)
                    .font(.bodySmall.weight(isActive ? .semibold : .regular))
            }
            .foregroundStyle(isActive ? Color.accent : Color.text2)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(isActive ? Color.accentLight : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
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
            // Scrollable pipeline area — 根据当前面板切换内容
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    switch activePanel {
                    case .script:
                        // 剧本面板：显示现有的 5 步管线
                        ForEach(sidebarSections) { section in
                            sectionView(section)
                        }
                    case .production:
                        // 制作面板：显示 6 个子标签列表
                        productionSidebarContent
                    case .exportPanel:
                        // 导出面板：显示导出概览
                        exportSidebarContent
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
        .animation(Animation.normal, value: activePanel)
    }

    // MARK: - 制作面板侧边栏内容

    /// 制作面板侧边栏：展示 6 个子标签的快速导航列表。
    private var productionSidebarContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // 标签分组标题
            Text("制作流程")
                .font(.labelSmall.weight(.bold))
                .foregroundStyle(Color.text3)
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, Spacing.xs)

            // 各制作步骤列表
            VStack(spacing: 0) {
                ForEach(Array(ProductionTab.allCases.enumerated()), id: \.element) { index, tab in
                    productionTabRow(tab, index: index, isLast: index == ProductionTab.allCases.count - 1)
                }
            }
        }
    }

    /// 制作面板的单个侧边栏行。
    private func productionTabRow(_ tab: ProductionTab, index: Int, isLast: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            // 图标圆圈
            ZStack {
                Circle()
                    .fill(Color.bg1)
                    .frame(width: 26, height: 26)
                Circle()
                    .stroke(Color.border0, lineWidth: 1)
                    .frame(width: 26, height: 26)
                Image(systemName: tab.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.text3)
            }
            .zIndex(1)

            // 标签标题
            Text(tab.rawValue)
                .font(.bodyMedium.weight(.regular))
                .foregroundStyle(Color.text1)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(alignment: .top) {
            // 连接线
            if !isLast {
                Rectangle()
                    .fill(Color.border0)
                    .frame(width: 1)
                    .offset(y: -4)
                    .padding(.leading, 21)
            }
        }
    }

    // MARK: - 导出面板侧边栏内容

    /// 导出面板侧边栏：显示镜头总览 / 视频合并 / 预览下载的概览。
    private var exportSidebarContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // 标签分组标题
            Text("导出流程")
                .font(.labelSmall.weight(.bold))
                .foregroundStyle(Color.text3)
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, Spacing.xs)

            // 导出概览列表
            VStack(spacing: 0) {
                exportStepRow(icon: "film.stack", title: "镜头总览", isLast: false)
                exportStepRow(icon: "arrow.triangle.merge", title: "视频合并", isLast: false)
                exportStepRow(icon: "play.rectangle", title: "预览下载", isLast: true)
            }

            // 镜头状态统计
            if !viewModel.storyboards.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Divider()
                        .padding(.vertical, Spacing.xs)

                    Text("镜头状态")
                        .font(.labelSmall.weight(.bold))
                        .foregroundStyle(Color.text3)

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: IconSize.xs))
                            .foregroundStyle(Color.statusSuccess)
                        Text("\(completedComposeCount) 已就绪")
                            .font(.labelSmall)
                            .foregroundStyle(Color.text2)
                    }

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "circle")
                            .font(.system(size: IconSize.xs))
                            .foregroundStyle(Color.text3)
                        Text("\(viewModel.storyboards.count - completedComposeCount) 待处理")
                            .font(.labelSmall)
                            .foregroundStyle(Color.text2)
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.top, Spacing.md)
            }
        }
    }

    /// 导出侧边栏的单个步骤行。
    private func exportStepRow(icon: String, title: String, isLast: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.bg1)
                    .frame(width: 26, height: 26)
                Circle()
                    .stroke(Color.border0, lineWidth: 1)
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.text3)
            }
            .zIndex(1)

            Text(title)
                .font(.bodyMedium.weight(.regular))
                .foregroundStyle(Color.text1)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(alignment: .top) {
            if !isLast {
                Rectangle()
                    .fill(Color.border0)
                    .frame(width: 1)
                    .offset(y: -4)
                    .padding(.leading, 21)
            }
        }
    }

    /// 已合成完成的镜头数量。
    private var completedComposeCount: Int {
        viewModel.storyboards.filter { sb in
            sb.composedVideoUrl != nil && !sb.composedVideoUrl!.isEmpty
        }.count
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
            // Progress header — 根据当前面板显示不同进度标题
            HStack {
                Text(activePanel == .script ? "剧本进度" : activePanel == .production ? "制作进度" : "导出进度")
                    .font(.labelSmall)
                    .foregroundStyle(Color.text3)
                Spacer()
                Text("\(progressCompleted)/\(progressTotal)")
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
                        .fill(sidebarProgressFraction >= 1.0 ? Color.statusSuccess : Color.accent)
                        .frame(width: max(0, geo.size.width * sidebarProgressFraction), height: 4)
                        .animation(Animation.normal, value: sidebarProgressFraction)
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

    /// 侧边栏底部进度：根据当前面板返回已完成步骤数。
    private var progressCompleted: Int {
        switch activePanel {
        case .script:
            return viewModel.completedStepCount
        case .production:
            // 制作面板：基于分镜和角色数据简单估算
            var count = 0
            if !viewModel.characters.isEmpty { count += 1 }
            if !viewModel.scenes.isEmpty { count += 1 }
            if !viewModel.storyboards.isEmpty { count += 1 }
            return count
        case .exportPanel:
            return completedComposeCount
        }
    }

    /// 侧边栏底部进度：根据当前面板返回总步骤数。
    private var progressTotal: Int {
        switch activePanel {
        case .script:
            return viewModel.totalSteps
        case .production:
            return 6
        case .exportPanel:
            return viewModel.storyboards.count
        }
    }

    /// 侧边栏底部进度百分比（0...1）。
    private var sidebarProgressFraction: Double {
        guard progressTotal > 0 else { return 0 }
        return Double(progressCompleted) / Double(progressTotal)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.error != nil {
                errorView
            } else {
                // 根据激活的顶级面板切换显示内容
                switch activePanel {
                case .script:
                    ScriptPanel(viewModel: viewModel)
                case .production:
                    ProductionPanel(viewModel: viewModel)
                case .exportPanel:
                    ExportPanel(viewModel: viewModel)
                }
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
