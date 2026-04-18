import SwiftUI

// MARK: - ScriptPanel

/// Container view for the script pipeline steps.
/// Switches its child based on `viewModel.currentStep`.
struct ScriptPanel: View {
    @ObservedObject var viewModel: StudioViewModel

    var body: some View {
        VStack(spacing: 0) {
            stepToolbar
            Divider()
            stepContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Step Toolbar

    private var stepToolbar: some View {
        HStack(spacing: Spacing.md) {
            // Step indicator: number + name
            HStack(spacing: Spacing.sm) {
                Text(String(format: "%02d", viewModel.currentStep.rawValue + 1))
                    .font(.headingLarge)
                    .foregroundStyle(Color.accent)
                    .monospacedDigit()
                Text(viewModel.currentStep.title)
                    .font(.headingMedium)
                    .foregroundStyle(Color.text0)
            }

            Spacer()

            // Step status badge
            stepStatusBadge
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
        .background(Color.bgCard)
    }

    @ViewBuilder
    private var stepStatusBadge: some View {
        let status = viewModel.status(for: viewModel.currentStep)
        switch status {
        case .completed:
            Label("已完成", systemImage: "checkmark.circle.fill")
                .font(.labelMedium)
                .foregroundStyle(Color.statusSuccess)
        case .inProgress:
            Label("进行中", systemImage: "ellipsis.circle.fill")
                .font(.labelMedium)
                .foregroundStyle(Color.statusInfo)
        case .notStarted:
            Label("未开始", systemImage: "circle")
                .font(.labelMedium)
                .foregroundStyle(Color.text3)
        }
    }

    // MARK: - Step Content Switch

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .rawContent:
            RawContentPanel(viewModel: viewModel)
        case .rewrite:
            RewritePanel(viewModel: viewModel)
        case .extract:
            StepPlaceholderView(
                icon: "person.2",
                title: "提取角色场景",
                description: "AI 自动分析剧本，提取角色信息和场景列表。",
                futureBatch: "E7.1"
            )
        case .voiceAssign:
            StepPlaceholderView(
                icon: "waveform",
                title: "分配音色",
                description: "为每个角色分配朗读音色，用于后续语音合成。",
                futureBatch: "E8.1"
            )
        case .storyboard:
            StepPlaceholderView(
                icon: "film",
                title: "分镜列表",
                description: "根据剧本和角色生成分镜列表，为制作视频做准备。",
                futureBatch: "E9.1"
            )
        }
    }
}

// MARK: - StepPlaceholderView

/// A centered placeholder for a pipeline step that will be filled in a future batch.
struct StepPlaceholderView: View {
    let icon: String
    let title: String
    let description: String
    let futureBatch: String

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Icon
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.text3)
                .frame(width: 80, height: 80)
                .background(Color.bg2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

            // Title
            Text(title)
                .font(.headingLarge)
                .foregroundStyle(Color.text1)

            // Description
            Text(description)
                .font(.bodyMedium)
                .foregroundStyle(Color.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            // Batch badge
            Text("将由 \(futureBatch) 实现")
                .font(.labelSmall)
                .foregroundStyle(Color.text3)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(Color.bg2)
                .clipShape(Capsule())

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
