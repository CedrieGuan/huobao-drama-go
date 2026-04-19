import SwiftUI

// MARK: - VideoComposeTab

/// 视频合成标签页。
/// 展示合成列表，支持批量合成已生成视频片段的最终视频。
struct VideoComposeTab: View {
    @ObservedObject var viewModel: StudioViewModel

    /// 是否正在批量合成。
    @State private var isBatchComposing = false

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
            if hasVideoReady {
                let total = videoReadyStoryboards.count
                let completed = videoReadyStoryboards.filter {
                    $0.composedVideoUrl != nil && !$0.composedVideoUrl!.isEmpty
                }.count
                Text("\(total) 个视频片段")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text2)
                Text("\u{00B7}")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text3)
                Text("已合成 \(completed)/\(total)")
                    .font(.labelMedium)
                    .foregroundStyle(completed == total ? Color.statusSuccess : Color.text2)
            }

            Spacer()

            // 合成进度提示
            if let progress = composeProgress {
                Text(progress)
                    .font(.labelMedium)
                    .foregroundStyle(Color.statusInfo)
            }

            // 批量合成按钮
            if hasVideoReady && !isBatchComposing {
                Button {
                    batchCompose()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: IconSize.xs, weight: .medium))
                        Text("批量合成")
                            .font(.bodySmall.weight(.medium))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgCard)
    }

    // MARK: - 内容区域

    @ViewBuilder
    private var contentArea: some View {
        if isBatchComposing {
            batchComposingView
        } else if hasVideoReady {
            composeResultsView
        } else {
            emptyView
        }
    }

    // MARK: - 空状态

    private var emptyView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.text3)
                .frame(width: 64, height: 64)
                .background(Color.bg2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

            Text("暂无视频可合成")
                .font(.headingLarge)
                .foregroundStyle(Color.text1)

            Text("请先完成视频生成步骤。已生成视频片段的分镜将显示在此处，可以合成为最终视频。")
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

    // MARK: - 批量合成状态

    private var batchComposingView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .tint(Color.accent)

            Text("正在合成视频...")
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

            // 进度条
            if let progress = composeProgress {
                Text(progress)
                    .font(.labelMedium)
                    .foregroundStyle(Color.text3)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg1)
    }

    // MARK: - 合成结果视图

    private var composeResultsView: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            // 左侧：合成统计侧边栏
            statisticsSidebar

            // 右侧：分镜视频列表 + 预览
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    // 最终合成预览
                    finalComposePreview

                    // 分镜视频片段列表
                    videoSegmentsSection
                }
                .padding(Spacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.bg1)
    }

    // MARK: - 统计侧边栏

    private var statisticsSidebar: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("视频合成")
                .font(.headingSmall)
                .foregroundStyle(Color.text0)

            Divider()

            // 视频片段统计
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("视频片段")
                    .font(.labelSmall)
                    .foregroundStyle(Color.text3)

                HStack(spacing: Spacing.sm) {
                    Text("\(videoReadyStoryboards.count)")
                        .font(.displayMedium)
                        .foregroundStyle(Color.text0)
                    Text("个")
                        .font(.bodySmall)
                        .foregroundStyle(Color.text2)
                }
            }

            // 合成进度
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("合成进度")
                    .font(.labelSmall)
                    .foregroundStyle(Color.text3)

                HStack(spacing: Spacing.sm) {
                    Text("\(composedCount)")
                        .font(.displayMedium)
                        .foregroundStyle(Color.accent)
                    Text("/ \(videoReadyStoryboards.count)")
                        .font(.bodySmall)
                        .foregroundStyle(Color.text3)
                }
            }

            // 总时长
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("总时长")
                    .font(.labelSmall)
                    .foregroundStyle(Color.text3)

                HStack(spacing: Spacing.sm) {
                    Text(formatDuration(totalDuration))
                        .font(.headingMedium)
                        .foregroundStyle(Color.text0)
                }
            }

            Divider()

            // 最终合成状态
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("最终合成")
                    .font(.labelSmall)
                    .foregroundStyle(Color.text3)

                if let videoUrl = viewModel.episode?.videoUrl, !videoUrl.isEmpty {
                    Label("已完成", systemImage: "checkmark.circle.fill")
                        .font(.labelMedium)
                        .foregroundStyle(Color.statusSuccess)
                } else {
                    Label("未合成", systemImage: "circle")
                        .font(.labelMedium)
                        .foregroundStyle(Color.text3)
                }
            }
        }
        .padding(Spacing.xl)
        .frame(width: 180)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .cardShadow()
    }

    // MARK: - 最终合成预览

    private var finalComposePreview: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionTitle("最终合成预览")

            if let videoUrl = viewModel.episode?.videoUrl, !videoUrl.isEmpty {
                VideoPlayerView(urlString: videoUrl, aspectRatio: 16 / 9)
                    .frame(maxWidth: 560, maxHeight: 315)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            } else {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color.text3)
                        .frame(width: 400, height: 225)
                        .background(Color.bg2)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

                    Text("尚未合成最终视频")
                        .font(.bodySmall)
                        .foregroundStyle(Color.text3)
                }
            }
        }
        .padding(Spacing.xl)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - 视频片段列表

    private var videoSegmentsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionTitle("视频片段")

            if videoReadyStoryboards.isEmpty {
                Text("暂无视频片段")
                    .font(.bodySmall)
                    .foregroundStyle(Color.text3)
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.lg)
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(videoReadyStoryboards) { storyboard in
                        videoSegmentRow(storyboard)
                    }
                }
            }
        }
    }

    private func videoSegmentRow(_ storyboard: Storyboard) -> some View {
        let hasComposed = storyboard.composedVideoUrl != nil && !storyboard.composedVideoUrl!.isEmpty
        let hasVideo = storyboard.videoUrl != nil && !storyboard.videoUrl!.isEmpty

        return HStack(spacing: Spacing.md) {
            // 编号
            Text(storyboard.label)
                .font(.labelMedium.weight(.medium))
                .foregroundStyle(Color.text0)
                .monospacedDigit()
                .frame(width: 24)

            // 缩略图
            Group {
                if let imageUrl = storyboard.composedImage, !imageUrl.isEmpty {
                    InlineAsyncImage(urlString: imageUrl, aspectRatio: 16 / 9)
                        .frame(width: 80, height: 45)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                } else {
                    RoundedRectangle(cornerRadius: Radius.xs)
                        .fill(Color.bg2)
                        .frame(width: 80, height: 45)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.text3)
                        }
                }
            }

            // 描述信息
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let desc = storyboard.description, !desc.isEmpty {
                    Text(desc)
                        .font(.bodySmall)
                        .foregroundStyle(Color.text1)
                        .lineLimit(1)
                } else if let title = storyboard.title, !title.isEmpty {
                    Text(title)
                        .font(.bodySmall)
                        .foregroundStyle(Color.text1)
                        .lineLimit(1)
                } else {
                    Text("镜头 \(storyboard.label)")
                        .font(.bodySmall)
                        .foregroundStyle(Color.text2)
                }

                HStack(spacing: Spacing.xs) {
                    if storyboard.duration > 0 {
                        Text("\(storyboard.duration)s")
                            .font(.labelSmall)
                            .foregroundStyle(Color.text3)
                    }
                }
            }

            Spacer()

            // 状态标签
            if hasComposed {
                TagView(text: "已合成", color: Color.statusSuccess, bgColor: Color.statusSuccessLight, size: .small)
            } else if hasVideo {
                TagView(text: "待合成", color: Color.statusWarning, bgColor: Color.statusWarningLight, size: .small)
            } else {
                TagView(text: "无视频", color: Color.text3, bgColor: Color.bg2, size: .small)
            }

            // 单个合成按钮
            if hasVideo && !hasComposed {
                Button {
                    composeSingle(storyboard)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: IconSize.xs, weight: .medium))
                        .foregroundStyle(Color.accent)
                }
                .buttonStyle(IconButtonStyle())
                .help("合成此片段")
            }
        }
        .padding(Spacing.md)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - 辅助方法

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headingSmall)
            .foregroundStyle(Color.text0)
    }

    /// 是否有已生成视频的分镜。
    private var hasVideoReady: Bool {
        !videoReadyStoryboards.isEmpty
    }

    /// 已生成视频的分镜列表。
    private var videoReadyStoryboards: [Storyboard] {
        viewModel.storyboards.filter { storyboard in
            storyboard.composedImage != nil && !storyboard.composedImage!.isEmpty
        }
    }

    /// 已合成的分镜数量。
    private var composedCount: Int {
        videoReadyStoryboards.filter {
            $0.composedVideoUrl != nil && !$0.composedVideoUrl!.isEmpty
        }.count
    }

    /// 所有视频片段的总时长（秒）。
    private var totalDuration: Int {
        videoReadyStoryboards.reduce(0) { $0 + $1.duration }
    }

    /// 合成进度文本。
    private var composeProgress: String? {
        guard isBatchComposing else { return nil }
        return "\(composedCount)/\(videoReadyStoryboards.count)"
    }

    /// 格式化总时长。
    private func formatDuration(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    /// 合成单个分镜视频。
    private func composeSingle(_ storyboard: Storyboard) {
        // TODO: 调用单个视频合成 API
        // Task { await viewModel.composeVideo(storyboardId: storyboard.id) }
    }

    /// 批量合成所有视频。
    private func batchCompose() {
        isBatchComposing = true
        // TODO: 调用批量视频合成 API
        // Task {
        //     await viewModel.batchComposeVideo()
        //     isBatchComposing = false
        // }

        // 模拟延时后恢复（待 API 接入后移除）
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            isBatchComposing = false
        }
    }
}
