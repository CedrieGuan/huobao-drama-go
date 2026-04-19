import SwiftUI
import AVFoundation

// MARK: - ExportPanel

/// 导出面板：镜头总览、视频合并、导出预览与下载。
/// 读取 StudioViewModel 中的分镜数据，展示各镜头的图片/视频/音频/合成状态，
/// 提供合并触发按钮和进度显示，以及最终视频的预览与下载。
struct ExportPanel: View {
    @ObservedObject var viewModel: StudioViewModel

    /// 合并进度（0...1）
    @State private var mergeProgress: Double = 0

    /// 是否正在合并
    @State private var isMerging = false

    /// 合并完成后的视频 URL
    @State private var mergedVideoURL: URL?

    /// 合并错误信息
    @State private var mergeError: String?

    /// 脉冲动画状态
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
            // 统计信息
            if hasStoryboards {
                let completedCount = completedShotCount
                Text("\(viewModel.storyboards.count) 镜头")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text2)
                Text("\u{00B7}")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text3)
                Text("\(completedCount)/\(viewModel.storyboards.count) 已就绪")
                    .font(.labelMedium)
                    .foregroundStyle(completedCount == viewModel.storyboards.count ? Color.statusSuccess : Color.text2)
            }

            Spacer()

            // 错误反馈
            if let error = mergeError {
                Text(error)
                    .font(.labelSmall)
                    .foregroundStyle(Color.statusError)
                    .lineLimit(1)
            }

            // 合并按钮
            if hasStoryboards {
                Button {
                    Task { await startMerge() }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.system(size: IconSize.xs, weight: .medium))
                        Text(isMerging ? "合并中..." : "开始合并")
                            .font(.bodySmall.weight(.medium))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isMerging || completedShotCount == 0)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgCard)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if isMerging {
            mergingView
        } else if hasStoryboards {
            resultsView
        } else {
            emptyView
        }
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // 图标
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.text3)
                .frame(width: 64, height: 64)
                .background(Color.bg2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

            // 标题
            Text("导出合成视频")
                .font(.headingLarge)
                .foregroundStyle(Color.text1)

            // 描述
            Text("完成所有分镜的图片生成、视频生成和音频合成后，可以将所有镜头合并为一部完整视频。")
                .font(.bodyMedium)
                .foregroundStyle(Color.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .lineSpacing(2)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg1)
    }

    // MARK: - Merging State

    private var mergingView: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // 进度圆环
            ZStack {
                Circle()
                    .stroke(Color.bg3, lineWidth: 6)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: mergeProgress)
                    .stroke(Color.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))

                Text("\(Int(mergeProgress * 100))%")
                    .font(.headingSmall.weight(.semibold))
                    .foregroundStyle(Color.text0)
            }

            Text("正在合并视频...")
                .font(.bodyMedium)
                .foregroundStyle(Color.text2)

            // 脉冲动画点
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
            // 左侧：镜头总览列表
            storyboardList

            // 右侧：合并进度 + 预览区域
            VStack(spacing: Spacing.xl) {
                // 合并进度区域
                mergeSection

                // 预览/下载区域
                previewSection
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(Spacing.xl)
        .background(Color.bg1)
    }

    // MARK: - Storyboard List

    private var storyboardList: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("镜头总览")
                .font(.headingSmall)
                .foregroundStyle(Color.text0)

            // 表头
            HStack(spacing: Spacing.sm) {
                Text("序号")
                    .frame(width: 36, alignment: .center)
                Spacer()
                Text("描述")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("图片")
                    .frame(width: 40, alignment: .center)
                Text("视频")
                    .frame(width: 40, alignment: .center)
                Text("音频")
                    .frame(width: 40, alignment: .center)
                Text("合成")
                    .frame(width: 40, alignment: .center)
            }
            .font(.labelSmall)
            .foregroundStyle(Color.text3)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)

            Divider()

            ScrollView {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(viewModel.storyboards) { storyboard in
                        storyboardStatusRow(storyboard)
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .frame(width: 420, maxHeight: .infinity)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .cardShadow()
    }

    // MARK: - Storyboard Status Row

    private func storyboardStatusRow(_ storyboard: Storyboard) -> some View {
        HStack(spacing: Spacing.sm) {
            // 序号
            Text(storyboard.label)
                .font(.labelMedium.weight(.medium))
                .foregroundStyle(Color.text0)
                .monospacedDigit()
                .frame(width: 36, alignment: .center)

            // 描述
            Text(storyboard.description ?? storyboard.action ?? "—")
                .font(.bodySmall)
                .foregroundStyle(Color.text1)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 图片状态
            statusIcon(for: imageStatus(storyboard))
                .frame(width: 40, alignment: .center)

            // 视频状态
            statusIcon(for: videoStatus(storyboard))
                .frame(width: 40, alignment: .center)

            // 音频状态
            statusIcon(for: audioStatus(storyboard))
                .frame(width: 40, alignment: .center)

            // 合成状态
            statusIcon(for: composeStatus(storyboard))
                .frame(width: 40, alignment: .center)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.bg1)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    // MARK: - Status Icon

    /// 根据状态返回对应的图标视图
    @ViewBuilder
    private func statusIcon(for status: ShotAssetStatus) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: IconSize.sm))
                .foregroundStyle(Color.statusSuccess)
        case .processing:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: IconSize.sm))
                .foregroundStyle(Color.statusWarning)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: IconSize.sm))
                .foregroundStyle(Color.statusError)
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: IconSize.sm))
                .foregroundStyle(Color.text3)
        }
    }

    // MARK: - Merge Section

    private var mergeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("视频合并")
                .font(.headingSmall)
                .foregroundStyle(Color.text0)

            // 进度条
            if isMerging || mergeProgress > 0 {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ProgressView(value: mergeProgress)
                        .tint(mergeProgress >= 1.0 ? Color.statusSuccess : Color.accent)

                    HStack {
                        Text(mergeProgress >= 1.0 ? "合并完成" : "合并中...")
                            .font(.labelSmall)
                            .foregroundStyle(Color.text2)
                        Spacer()
                        Text("\(Int(mergeProgress * 100))%")
                            .font(.labelSmall)
                            .foregroundStyle(Color.text3)
                            .monospacedDigit()
                    }
                }
            }

            // 合并就绪状态提示
            if !isMerging && mergeProgress == 0 {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "info.circle")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(Color.statusInfo)
                    Text(mergeReadyDescription)
                        .font(.bodySmall)
                        .foregroundStyle(Color.text2)
                }
            }

            // 合并完成状态
            if mergeProgress >= 1.0 && mergedVideoURL != nil {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(Color.statusSuccess)
                    Text("视频合并成功")
                        .font(.bodySmall)
                        .foregroundStyle(Color.statusSuccess)
                }
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .cardShadow()
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("导出预览")
                .font(.headingSmall)
                .foregroundStyle(Color.text0)

            if let url = mergedVideoURL {
                // 视频播放器区域
                videoPlayerView(url: url)
            } else if hasComposedVideos {
                // 有部分合成完成的镜头但没有最终合并视频
                previewPlaceholder(
                    icon: "film.stack",
                    text: "已有 \(composedVideoCount) 个镜头合成完成，点击上方「开始合并」生成完整视频"
                )
            } else {
                // 没有可预览的视频
                previewPlaceholder(
                    icon: "video.slash",
                    text: "尚无合成视频，请先完成各镜头的图片、视频和音频生成"
                )
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .cardShadow()
    }

    // MARK: - Video Player

    @ViewBuilder
    private func videoPlayerView(url: URL) -> some View {
        VStack(spacing: Spacing.md) {
            // 视频预览框
            VideoPlayerPreview(url: url)
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))

            // 下载按钮
            HStack {
                Spacer()
                Button {
                    downloadVideo(url: url)
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: IconSize.xs, weight: .medium))
                        Text("下载视频")
                            .font(.bodySmall.weight(.medium))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    // MARK: - Preview Placeholder

    private func previewPlaceholder(icon: String, text: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.text3)
                .frame(width: 64, height: 64)
                .background(Color.bg2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

            Text(text)
                .font(.bodySmall)
                .foregroundStyle(Color.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
        .background(Color.bg1)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Status Computation

    /// 镜头资产状态枚举
    private enum ShotAssetStatus {
        case pending
        case processing
        case completed
        case failed
    }

    /// 图片状态
    private func imageStatus(_ sb: Storyboard) -> ShotAssetStatus {
        if sb.composedImage != nil && !sb.composedImage!.isEmpty {
            return .completed
        }
        if sb.status == "processing" || sb.status == "in_production" {
            return .processing
        }
        if sb.status == "failed" { return .failed }
        return .pending
    }

    /// 视频状态
    private func videoStatus(_ sb: Storyboard) -> ShotAssetStatus {
        if sb.videoUrl != nil && !sb.videoUrl!.isEmpty {
            return .completed
        }
        if sb.status == "processing" || sb.status == "in_production" {
            return .processing
        }
        if sb.status == "failed" { return .failed }
        return .pending
    }

    /// 音频状态
    private func audioStatus(_ sb: Storyboard) -> ShotAssetStatus {
        if sb.ttsAudioUrl != nil && !sb.ttsAudioUrl!.isEmpty {
            return .completed
        }
        return .pending
    }

    /// 合成状态
    private func composeStatus(_ sb: Storyboard) -> ShotAssetStatus {
        if sb.composedVideoUrl != nil && !sb.composedVideoUrl!.isEmpty {
            return .completed
        }
        if sb.status == "processing" || sb.status == "in_production" {
            return .processing
        }
        if sb.status == "failed" { return .failed }
        return .pending
    }

    // MARK: - Helpers

    /// 是否有分镜数据
    private var hasStoryboards: Bool {
        !viewModel.storyboards.isEmpty
    }

    /// 已就绪（合成完成）的镜头数
    private var completedShotCount: Int {
        viewModel.storyboards.filter { sb in
            sb.composedVideoUrl != nil && !sb.composedVideoUrl!.isEmpty
        }.count
    }

    /// 是否有部分镜头已合成视频
    private var hasComposedVideos: Bool {
        composedVideoCount > 0
    }

    /// 已合成视频的镜头数
    private var composedVideoCount: Int {
        viewModel.storyboards.filter { sb in
            sb.composedVideoUrl != nil && !sb.composedVideoUrl!.isEmpty
        }.count
    }

    /// 合并就绪描述文案
    private var mergeReadyDescription: String {
        let total = viewModel.storyboards.count
        let ready = completedShotCount
        if ready == 0 {
            return "尚无镜头完成合成，请先完成图片、视频和音频的生成。"
        } else if ready < total {
            return "\(ready)/\(total) 个镜头已就绪，未就绪的镜头将使用空白画面。"
        } else {
            return "全部 \(total) 个镜头已就绪，可以开始合并。"
        }
    }

    // MARK: - Actions

    /// 开始合并视频
    private func startMerge() async {
        isMerging = true
        mergeError = nil
        mergeProgress = 0
        mergedVideoURL = nil

        // TODO: 调用 ViewModel 的合并方法，目前通过 MergeAPI 触发合并
        // 合并完成后轮询状态获取 merged_url
        do {
            // 模拟进度更新（实际应由后端轮询驱动）
            // TODO: 替换为 viewModel.runMerge() + 轮询进度的实现
            try await APIEndpoints.MergeAPI.episode(episodeId: viewModel.episodeId)

            // 模拟进度动画
            for step in stride(from: 0.0, through: 1.0, by: 0.05) {
                mergeProgress = step
                try? await Task.sleep(for: .milliseconds(100))
            }

            // TODO: 从后端获取合并后的视频 URL
            // 目前使用 pipelineStatus 中的 mergedUrl
            let pipelineStatus = try await APIEndpoints.EpisodeAPI.pipelineStatus(episodeId: viewModel.episodeId)
            if let urlStr = pipelineStatus.steps.mergeEpisode.mergedUrl, !urlStr.isEmpty {
                mergedVideoURL = URL(string: urlStr)
            }

            mergeProgress = 1.0
        } catch {
            mergeError = error.localizedDescription
        }

        isMerging = false
    }

    /// 下载视频到本地，使用 DownloadExportService 的 saveWithPanel 方法。
    private func downloadVideo(url: URL) {
        let suggestedName = "\(viewModel.drama?.title ?? "video")_episode_\(viewModel.episodeId).mp4"
        Task {
            do {
                try await DownloadExportService.shared.saveWithPanel(
                    from: url.absoluteString,
                    suggestedName: suggestedName
                )
            } catch {
                mergeError = "下载失败: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - VideoPlayerPreview

/// 简单的视频预览视图，使用 AVPlayer 播放指定 URL 的视频。
struct VideoPlayerPreview: View {
    let url: URL

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayerNSView(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 没有加载出播放器时的占位
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.text3)
                    Text("视频加载中...")
                        .font(.bodySmall)
                        .foregroundStyle(Color.text2)
                }
            }
        }
        .onAppear {
            player = AVPlayer(url: url)
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

// MARK: - VideoPlayerNSView

/// macOS 原生 AVPlayerViewController 的 NSView 包装。
struct VideoPlayerNSView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}
