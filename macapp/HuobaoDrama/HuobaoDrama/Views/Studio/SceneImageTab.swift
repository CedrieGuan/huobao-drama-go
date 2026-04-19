import SwiftUI

// MARK: - SceneImageTab

/// 场景图片生成标签页。
/// 展示场景列表，支持批量生成场景背景图片。
struct SceneImageTab: View {
    @ObservedObject var viewModel: StudioViewModel

    /// 当前选中查看详情的场景 ID。
    @State private var selectedSceneId: Int? = nil

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
                let completed = viewModel.scenes.filter { $0.imageUrl != nil && !$0.imageUrl!.isEmpty }.count
                Text("\(viewModel.scenes.count) 场景")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text2)
                Text("\u{00B7}")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text3)
                Text("已完成 \(completed)/\(viewModel.scenes.count)")
                    .font(.labelMedium)
                    .foregroundStyle(completed == viewModel.scenes.count ? Color.statusSuccess : Color.text2)
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
                .disabled(pendingScenes.isEmpty)
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

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.text3)
                .frame(width: 64, height: 64)
                .background(Color.bg2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

            Text("暂无场景数据")
                .font(.headingLarge)
                .foregroundStyle(Color.text1)

            Text("请先在剧本管线中完成场景提取步骤，再进行场景图片生成。")
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

            Text("正在批量生成场景图片...")
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
            // 左侧：场景列表
            sceneList

            Divider()

            // 右侧：场景详情 / 图片预览
            detailPanel
        }
        .background(Color.bg1)
    }

    // MARK: - 场景列表

    private var sceneList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xs) {
                ForEach(viewModel.scenes) { scene in
                    sceneListItem(scene)
                }
            }
            .padding(Spacing.sm)
        }
        .frame(width: 300)
        .background(Color.bgCard)
    }

    private func sceneListItem(_ scene: Scene) -> some View {
        let isSelected = selectedSceneId == scene.id
        let hasImage = scene.imageUrl != nil && !scene.imageUrl!.isEmpty

        return Button {
            selectedSceneId = scene.id
        } label: {
            HStack(spacing: Spacing.md) {
                // 场景图标
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: IconSize.sm))
                    .foregroundStyle(isSelected ? Color.textInverse : Color.accent)
                    .frame(width: 32, height: 32)

                // 信息
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.sm) {
                        Text(scene.location)
                            .font(.bodyMedium.weight(.medium))
                            .foregroundStyle(isSelected ? Color.textInverse : Color.text0)
                            .lineLimit(1)

                        if !scene.time.isEmpty {
                            TagView(
                                text: scene.time,
                                color: isSelected ? Color.textInverse.opacity(0.9) : Color.text2,
                                bgColor: isSelected ? Color.white.opacity(0.15) : Color.bg2,
                                size: .small
                            )
                        }
                    }

                    if !scene.prompt.isEmpty {
                        Text(scene.prompt)
                            .font(.labelSmall)
                            .foregroundStyle(isSelected ? Color.textInverse.opacity(0.7) : Color.text2)
                            .lineLimit(1)
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

    private var selectedScene: Scene? {
        guard let id = selectedSceneId else { return nil }
        return viewModel.scenes.first(where: { $0.id == id })
    }

    private var detailPanel: some View {
        Group {
            if let scene = selectedScene {
                sceneDetailView(scene)
            } else {
                noSelectionView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSelectionView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.text3)

            Text("选择一个场景查看详情")
                .font(.bodyMedium)
                .foregroundStyle(Color.text3)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sceneDetailView(_ scene: Scene) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // 标题行
                detailHeader(scene)

                // 场景信息卡片
                sceneInfoCard(scene)

                // 图片预览区域
                imagePreviewSection(scene)
            }
            .padding(Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg1)
    }

    private func detailHeader(_ scene: Scene) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(scene.location)
                    .font(.displaySmall)
                    .foregroundStyle(Color.text0)

                HStack(spacing: Spacing.sm) {
                    TagView(text: scene.time, size: .small)
                    if scene.storyboardCount > 0 {
                        TagView(
                            text: "\(scene.storyboardCount) 个分镜",
                            color: Color.text2,
                            bgColor: Color.bg2,
                            size: .small
                        )
                    }
                }
            }

            Spacer()

            // 生成按钮
            let hasImage = scene.imageUrl != nil && !scene.imageUrl!.isEmpty
            Button {
                generateSceneImage(scene)
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: hasImage ? "arrow.clockwise" : "wand.and.stars")
                        .font(.system(size: IconSize.xs, weight: .medium))
                    Text(hasImage ? "重新生成" : "生成场景")
                        .font(.bodySmall.weight(.medium))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func sceneInfoCard(_ scene: Scene) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionTitle("场景描述")

            if !scene.prompt.isEmpty {
                Text(scene.prompt)
                    .font(.bodySmall)
                    .foregroundStyle(Color.text1)
                    .lineSpacing(2)
            }
        }
        .padding(Spacing.xl)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func imagePreviewSection(_ scene: Scene) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionTitle("场景图片")

            if let imageUrl = scene.imageUrl, !imageUrl.isEmpty {
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

                    Text("尚未生成场景图片")
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

    /// 是否有场景结果可显示。
    private var hasResults: Bool {
        !viewModel.scenes.isEmpty
    }

    /// 未生成图片的场景列表。
    private var pendingScenes: [Scene] {
        viewModel.scenes.filter { $0.imageUrl == nil || $0.imageUrl!.isEmpty }
    }

    /// 生成单个场景图片。
    private func generateSceneImage(_ scene: Scene) {
        // TODO: 调用场景图片生成 API
        // Task { await viewModel.generateSceneImage(sceneId: scene.id) }
    }

    /// 批量生成所有待生成的场景图片。
    private func batchGenerate() {
        isBatchGenerating = true
        // TODO: 调用批量场景图片生成 API
        // Task {
        //     await viewModel.batchGenerateSceneImages()
        //     isBatchGenerating = false
        // }

        // 模拟延时后恢复（待 API 接入后移除）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isBatchGenerating = false
        }
    }
}
