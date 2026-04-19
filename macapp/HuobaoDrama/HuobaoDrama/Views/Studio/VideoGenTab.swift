import SwiftUI

// MARK: - VideoGenTab

/// 视频生成标签页。
/// 展示已生成图片的分镜列表，支持单个和批量生成视频片段。
struct VideoGenTab: View {
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
                let total = imageReadyStoryboards.count
                let completed = imageReadyStoryboards.filter {
                    $0.videoUrl != nil && !$0.videoUrl!.isEmpty
                }.count
                Text("\(total) 可生成")
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
                        Text("批量生成视频")
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

            Image(systemName: "video.badge.plus")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.text3)
                .frame(width: 64, height: 64)
                .background(Color.bg2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

            Text("暂无可生成的视频")
                .font(.headingLarge)
                .foregroundStyle(Color.text1)

            Text("请先完成镜头图片生成步骤。已生成图片的分镜将显示在此处，可以生成对应的视频片段。")
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

            Text("正在批量生成视频...")
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

            // 右侧：分镜详情 / 视频预览
            detailPanel
        }
        .background(Color.bg1)
    }

    // MARK: - 分镜列表

    private var storyboardList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xs) {
                ForEach(imageReadyStoryboards) { storyboard in
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
        let hasVideo = storyboard.videoUrl != nil && !storyboard.videoUrl!.isEmpty

        return Button {
            selectedStoryboardId = storyboard.id
        } label: {
            HStack(spacing: Spacing.md) {
                // 缩略图预览
                Group {
                    if let imageUrl = storyboard.composedImage, !imageUrl.isEmpty {
                        InlineAsyncImage(urlString: imageUrl, aspectRatio: 16 / 9)
                            .frame(width: 48, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                    } else {
                        RoundedRectangle(cornerRadius: Radius.xs)
                            .fill(Color.bg2)
                            .frame(width: 48, height: 28)
                            .overlay {
                                Image(systemName: "film")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.text3)
                            }
                    }
                }

                // 信息
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.sm) {
                        Text(storyboard.label)
                            .font(.labelMedium.weight(.medium))
                            .foregroundStyle(isSelected ? Color.textInverse : Color.text0)
                            .monospacedDigit()

                        if storyboard.duration > 0 {
                            Text("\(storyboard.duration)s")
                                .font(.labelSmall)
                                .foregroundStyle(isSelected ? Color.textInverse.opacity(0.7) : Color.text3)
                        }
                    }

                    if let desc = storyboard.description, !desc.isEmpty {
                        Text(desc)
                            .font(.labelSmall)
                            .foregroundStyle(isSelected ? Color.textInverse.opacity(0.7) : Color.text2)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // 状态指示
                if hasVideo {
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
        return imageReadyStoryboards.first(where: { $0.id == id })
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

            Image(systemName: "video.badge.plus")
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

                // 视频提示词卡片
                videoPromptCard(storyboard)

                // 视频预览区域
                videoPreviewSection(storyboard)

                // 原始图片参考
                sourceImageSection(storyboard)
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
            let hasVideo = storyboard.videoUrl != nil && !storyboard.videoUrl!.isEmpty
            Button {
                generateVideo(storyboard)
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: hasVideo ? "arrow.clockwise" : "video.badge.plus")
                        .font(.system(size: IconSize.xs, weight: .medium))
                    Text(hasVideo ? "重新生成" : "生成视频")
                        .font(.bodySmall.weight(.medium))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func videoPromptCard(_ storyboard: Storyboard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionTitle("视频提示词")

            if let videoPrompt = storyboard.videoPrompt, !videoPrompt.isEmpty {
                Text(videoPrompt)
                    .font(.monoMedium)
                    .foregroundStyle(Color.text1)
                    .lineSpacing(2)
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bg1)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            } else {
                Text("暂无视频提示词")
                    .font(.bodySmall)
                    .foregroundStyle(Color.text3)
            }

            // 运动信息
            if let movement = storyboard.movement, !movement.isEmpty {
                Divider()
                promptRow(label: "镜头运动", value: movement)
            }
        }
        .padding(Spacing.xl)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func videoPreviewSection(_ storyboard: Storyboard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionTitle("视频预览")

            if let videoUrl = storyboard.videoUrl, !videoUrl.isEmpty {
                VideoPlayerView(urlString: videoUrl, aspectRatio: 16 / 9)
                    .frame(maxWidth: 480, maxHeight: 270)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            } else {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.text3)
                        .frame(width: 320, height: 180)
                        .background(Color.bg2)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

                    Text("尚未生成视频")
                        .font(.bodySmall)
                        .foregroundStyle(Color.text3)
                }
            }
        }
        .padding(Spacing.xl)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func sourceImageSection(_ storyboard: Storyboard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionTitle("源图片")

            if let imageUrl = storyboard.composedImage, !imageUrl.isEmpty {
                InlineAsyncImage(urlString: imageUrl, aspectRatio: 16 / 9)
                    .frame(maxWidth: 320, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            } else {
                Text("无源图片")
                    .font(.bodySmall)
                    .foregroundStyle(Color.text3)
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

    /// 是否有可显示的结果。
    private var hasResults: Bool {
        !imageReadyStoryboards.isEmpty
    }

    /// 已生成图片的分镜列表（可生成视频的）。
    private var imageReadyStoryboards: [Storyboard] {
        viewModel.storyboards.filter { storyboard in
            guard let image = storyboard.composedImage else { return false }
            return !image.isEmpty
        }
    }

    /// 未生成视频的分镜列表。
    private var pendingStoryboards: [Storyboard] {
        imageReadyStoryboards.filter { $0.videoUrl == nil || $0.videoUrl!.isEmpty }
    }

    /// 生成单个分镜视频。
    private func generateVideo(_ storyboard: Storyboard) {
        // TODO: 调用视频生成 API
        // Task { await viewModel.generateVideo(storyboardId: storyboard.id) }
    }

    /// 批量生成所有待生成的视频。
    private func batchGenerate() {
        isBatchGenerating = true
        // TODO: 调用批量视频生成 API
        // Task {
        //     await viewModel.batchGenerateVideos()
        //     isBatchGenerating = false
        // }

        // 模拟延时后恢复（待 API 接入后移除）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isBatchGenerating = false
        }
    }
}
