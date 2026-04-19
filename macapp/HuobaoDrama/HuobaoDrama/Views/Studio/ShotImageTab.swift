import SwiftUI

// MARK: - ShotImageTab

/// 镜头图片生成标签页。
/// 展示分镜列表，支持单个和批量生成镜头图片（composed_image）。
struct ShotImageTab: View {
    @ObservedObject var viewModel: StudioViewModel

    /// 当前选中查看详情的分镜 ID。
    @State private var selectedStoryboardId: Int? = nil

    /// 是否正在批量生成。
    @State private var isBatchGenerating = false

    // 脉冲动画状态
    @State private var pulsePhase = false

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()
            contentArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 操作栏

    private var actionBar: some View {
        HStack(spacing: Spacing.md) {
            // 统计信息
            if hasResults {
                let total = viewModel.storyboards.count
                let completed = viewModel.storyboards.filter {
                    $0.composedImage != nil && !$0.composedImage!.isEmpty
                }.count
                Text("\(total) 镜头")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text2)
                Text("\u{00B7}")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text3)
                Text("已完成 \(completed)/\(total)")
                    .font(.labelMedium)
                    .foregroundStyle(completed == total ? Color.statusSuccess : Color.text2)
            }

            Spacer()

            // 批量生成按钮
            if hasResults && !isBatchGenerating {
                Button {
                    batchGenerate()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: IconSize.xs, weight: .medium))
                        Text("批量生成")
                            .font(.bodySmall.weight(.medium))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(pendingStoryboards.isEmpty)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgCard)
    }

    // MARK: - 内容区域

    @ViewBuilder
    private var contentArea: some View {
        if isBatchGenerating {
            batchLoadingView
        } else if hasResults {
            resultsView
        } else {
            emptyView
        }
    }

    // MARK: - 空状态

    private var emptyView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "film")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.text3)
                .frame(width: 64, height: 64)
                .background(Color.bg2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

            Text("暂无分镜数据")
                .font(.headingLarge)
                .foregroundStyle(Color.text1)

            Text("请先完成分镜拆解步骤。分镜列表将在此处显示，您可以生成每帧镜头图片。")
                .font(.bodyMedium)
                .foregroundStyle(Color.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .lineSpacing(2)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg1)
    }

    // MARK: - 批量加载状态

    private var batchLoadingView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .tint(Color.accent)

            Text("正在批量生成镜头图片...")
                .font(.bodyMedium)
                .foregroundStyle(Color.text2)

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

    // MARK: - 结果视图（左右分栏）

    private var resultsView: some View {
        HStack(spacing: 0) {
            // 左侧：分镜列表
            storyboardList

            Divider()

            // 右侧：分镜详情 / 图片预览
            detailPanel
        }
        .background(Color.bg1)
    }

    // MARK: - 分镜列表

    private var storyboardList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xs) {
                ForEach(viewModel.storyboards) { storyboard in
                    storyboardListItem(storyboard)
                }
            }
            .padding(Spacing.sm)
        }
        .frame(width: 300)
        .background(Color.bgCard)
    }

    private func storyboardListItem(_ storyboard: Storyboard) -> some View {
        let isSelected = selectedStoryboardId == storyboard.id
        let hasImage = storyboard.composedImage != nil && !storyboard.composedImage!.isEmpty

        return Button {
            selectedStoryboardId = storyboard.id
        } label: {
            HStack(spacing: Spacing.md) {
                // 编号
                Text(storyboard.label)
                    .font(.labelMedium.weight(.medium))
                    .foregroundStyle(isSelected ? Color.textInverse : Color.text0)
                    .monospacedDigit()

                // 信息
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    // 镜头描述
                    if let desc = storyboard.description, !desc.isEmpty {
                        Text(desc)
                            .font(.bodySmall)
                            .foregroundStyle(isSelected ? Color.textInverse.opacity(0.9) : Color.text1)
                            .lineLimit(1)
                    }

                    // 景别标签
                    HStack(spacing: Spacing.xs) {
                        if let shotType = storyboard.shotType, !shotType.isEmpty {
                            TagView(
                                text: shotType,
                                color: isSelected ? Color.textInverse.opacity(0.9) : Color.accent,
                                bgColor: isSelected ? Color.white.opacity(0.15) : Color.accentLight,
                                size: .small
                            )
                        }
                        if storyboard.duration > 0 {
                            Text("\(storyboard.duration)s")
                                .font(.labelSmall)
                                .foregroundStyle(isSelected ? Color.textInverse.opacity(0.7) : Color.text3)
                        }
                    }
                }

                Spacer()

                // 状态指示
                if hasImage {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(isSelected ? Color.textInverse : Color.statusSuccess)
                } else {
                    StatusDot(status: "pending", size: 8)
                }
            }
            .padding(Spacing.sm)
            .background(isSelected ? Color.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 详情面板

    private var selectedStoryboard: Storyboard? {
        guard let id = selectedStoryboardId else { return nil }
        return viewModel.storyboards.first(where: { $0.id == id })
    }

    private var detailPanel: some View {
        Group {
            if let storyboard = selectedStoryboard {
                storyboardDetailView(storyboard)
            } else {
                noSelectionView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSelectionView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "film")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.text3)

            Text("选择一个镜头查看详情")
                .font(.bodyMedium)
                .foregroundStyle(Color.text3)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func storyboardDetailView(_ storyboard: Storyboard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // 标题行
                detailHeader(storyboard)

                // 画面描述与提示词
                promptInfoCard(storyboard)

                // 图片预览区域
                imagePreviewSection(storyboard)
            }
            .padding(Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg1)
    }

    private func detailHeader(_ storyboard: Storyboard) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Text(storyboard.label)
                        .font(.displayMedium)
                        .foregroundStyle(Color.accent)
                        .monospacedDigit()

                    if let title = storyboard.title, !title.isEmpty {
                        Text(title)
                            .font(.headingSmall)
                            .foregroundStyle(Color.text0)
                    }
                }

                HStack(spacing: Spacing.sm) {
                    if let shotType = storyboard.shotType, !shotType.isEmpty {
                        TagView(text: shotType, size: .small)
                    }
                    if let angle = storyboard.angle, !angle.isEmpty {
                        TagView(text: angle, color: Color.text2, bgColor: Color.bg2, size: .small)
                    }
                    if storyboard.duration > 0 {
                        TagView(
                            text: "\(storyboard.duration)s",
                            color: Color.text2,
                            bgColor: Color.bg2,
                            size: .small
                        )
                    }
                }
            }

            Spacer()

            // 生成按钮
            let hasImage = storyboard.composedImage != nil && !storyboard.composedImage!.isEmpty
            Button {
                generateShotImage(storyboard)
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: hasImage ? "arrow.clockwise" : "wand.and.stars")
                        .font(.system(size: IconSize.xs, weight: .medium))
                    Text(hasImage ? "重新生成" : "生成图片")
                        .font(.bodySmall.weight(.medium))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func promptInfoCard(_ storyboard: Storyboard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionTitle("画面信息")

            // 动作描述
            if let action = storyboard.action, !action.isEmpty {
                promptRow(label: "动作", value: action)
            }

            // 结果描述
            if let result = storyboard.result, !result.isEmpty {
                promptRow(label: "结果", value: result)
            }

            // 氛围
            if let atmosphere = storyboard.atmosphere, !atmosphere.isEmpty {
                promptRow(label: "氛围", value: atmosphere)
            }

            Divider()

            // 图片提示词
            if let imagePrompt = storyboard.imagePrompt, !imagePrompt.isEmpty {
                sectionTitle("图片提示词")
                Text(imagePrompt)
                    .font(.monoMedium)
                    .foregroundStyle(Color.text1)
                    .lineSpacing(2)
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bg1)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }

            // 关联角色
            if !storyboard.characters.isEmpty {
                Divider()
                sectionTitle("关联角色")
                HStack(spacing: Spacing.sm) {
                    ForEach(storyboard.characters) { character in
                        HStack(spacing: Spacing.xs) {
                            Text(String(character.name.prefix(1)))
                                .font(.labelSmall.weight(.medium))
                                .foregroundStyle(Color.textInverse)
                                .frame(width: 18, height: 18)
                                .background(Color.accent)
                                .clipShape(Circle())
                            Text(character.name)
                                .font(.bodySmall)
                                .foregroundStyle(Color.text1)
                        }
                    }
                }
            }
        }
        .padding(Spacing.xl)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func imagePreviewSection(_ storyboard: Storyboard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionTitle("镜头图片")

            if let imageUrl = storyboard.composedImage, !imageUrl.isEmpty {
                InlineAsyncImage(urlString: imageUrl, aspectRatio: 16 / 9)
                    .frame(maxWidth: 480, maxHeight: 270)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            } else {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "photo")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.text3)
                        .frame(width: 320, height: 180)
                        .background(Color.bg2)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

                    Text("尚未生成镜头图片")
                        .font(.bodySmall)
                        .foregroundStyle(Color.text3)
                }
            }
        }
        .padding(Spacing.xl)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - 辅助方法

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headingSmall)
            .foregroundStyle(Color.text0)
    }

    private func promptRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(.labelSmall)
                .foregroundStyle(Color.text3)
            Text(value)
                .font(.bodySmall)
                .foregroundStyle(Color.text1)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 是否有分镜结果可显示。
    private var hasResults: Bool {
        !viewModel.storyboards.isEmpty
    }

    /// 未生成图片的分镜列表。
    private var pendingStoryboards: [Storyboard] {
        viewModel.storyboards.filter { $0.composedImage == nil || $0.composedImage!.isEmpty }
    }

    /// 生成单个镜头图片。
    private func generateShotImage(_ storyboard: Storyboard) {
        // TODO: 调用镜头图片生成 API
        // Task { await viewModel.generateShotImage(storyboardId: storyboard.id) }
    }

    /// 批量生成所有待生成的镜头图片。
    private func batchGenerate() {
        isBatchGenerating = true
        // TODO: 调用批量镜头图片生成 API
        // Task {
        //     await viewModel.batchGenerateShotImages()
        //     isBatchGenerating = false
        // }

        // 模拟延时后恢复（待 API 接入后移除）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isBatchGenerating = false
        }
    }
}
