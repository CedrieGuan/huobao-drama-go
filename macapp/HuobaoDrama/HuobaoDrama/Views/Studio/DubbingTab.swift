import SwiftUI

// MARK: - DubbingTab

/// 配音生成标签页。
/// 展示含有对话的分镜列表，支持 TTS 配音生成和播放预览。
struct DubbingTab: View {
    @ObservedObject var viewModel: StudioViewModel

    /// 当前选中查看详情的分镜 ID。
    @State private var selectedStoryboardId: Int? = nil

    /// 是否正在批量生成配音。
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
                let total = dialogueStoryboards.count
                let completed = dialogueStoryboards.filter {
                    $0.ttsAudioUrl != nil && !$0.ttsAudioUrl!.isEmpty
                }.count
                Text("\(total) 条对白")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text2)
                Text("\u{00B7}")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text3)
                Text("已配音 \(completed)/\(total)")
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
                        Text("批量配音")
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

            Image(systemName: "waveform")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.text3)
                .frame(width: 64, height: 64)
                .background(Color.bg2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

            Text("暂无对白分镜")
                .font(.headingLarge)
                .foregroundStyle(Color.text1)

            Text("请先完成分镜拆解步骤。含有对白的分镜将显示在此处。")
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

            Text("正在批量生成配音...")
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

            // 右侧：分镜详情 / 音频预览
            detailPanel
        }
        .background(Color.bg1)
    }

    // MARK: - 分镜列表

    private var storyboardList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xs) {
                ForEach(dialogueStoryboards) { storyboard in
                    storyboardListItem(storyboard)
                }
            }
            .padding(Spacing.sm)
        }
        .frame(width: 320)
        .background(Color.bgCard)
    }

    private func storyboardListItem(_ storyboard: Storyboard) -> some View {
        let isSelected = selectedStoryboardId == storyboard.id
        let hasAudio = storyboard.ttsAudioUrl != nil && !storyboard.ttsAudioUrl!.isEmpty

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
                    // 对白预览
                    if let dialogue = storyboard.dialogue, !dialogue.isEmpty {
                        Text(dialogue)
                            .font(.bodySmall)
                            .foregroundStyle(isSelected ? Color.textInverse.opacity(0.9) : Color.text1)
                            .lineLimit(2)
                    }

                    // 角色信息
                    if !storyboard.characters.isEmpty {
                        HStack(spacing: Spacing.xs) {
                            ForEach(storyboard.characters.prefix(3)) { character in
                                Text(String(character.name.prefix(1)))
                                    .font(.labelSmall.weight(.medium))
                                    .foregroundStyle(isSelected ? Color.textInverse : Color.accent)
                                    .frame(width: 16, height: 16)
                                    .background(isSelected ? Color.white.opacity(0.2) : Color.accentLight)
                                    .clipShape(Circle())
                            }
                            if storyboard.characters.count > 3 {
                                Text("+\(storyboard.characters.count - 3)")
                                    .font(.labelSmall)
                                    .foregroundStyle(isSelected ? Color.textInverse.opacity(0.7) : Color.text3)
                            }
                        }
                    }
                }

                Spacer()

                // 状态指示
                if hasAudio {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: IconSize.xs))
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
        return dialogueStoryboards.first(where: { $0.id == id })
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

            Image(systemName: "waveform")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.text3)

            Text("选择一条对白查看详情")
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

                // 对白信息卡片
                dialogueInfoCard(storyboard)

                // 音频预览区域
                audioPreviewSection(storyboard)
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

                // 角色标签
                if !storyboard.characters.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        ForEach(storyboard.characters) { character in
                            TagView(
                                text: character.name,
                                size: .small
                            )
                        }
                    }
                }
            }

            Spacer()

            // 生成配音按钮
            let hasAudio = storyboard.ttsAudioUrl != nil && !storyboard.ttsAudioUrl!.isEmpty
            Button {
                generateDubbing(storyboard)
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: hasAudio ? "arrow.clockwise" : "waveform.badge.plus")
                        .font(.system(size: IconSize.xs, weight: .medium))
                    Text(hasAudio ? "重新生成" : "生成配音")
                        .font(.bodySmall.weight(.medium))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func dialogueInfoCard(_ storyboard: Storyboard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionTitle("对白内容")

            if let dialogue = storyboard.dialogue, !dialogue.isEmpty {
                Text(dialogue)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.text1)
                    .lineSpacing(3)
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bg1)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }

            // 关联角色信息
            if !storyboard.characters.isEmpty {
                Divider()

                sectionTitle("关联角色")

                ForEach(storyboard.characters) { character in
                    HStack(spacing: Spacing.sm) {
                        Text(String(character.name.prefix(1)))
                            .font(.labelSmall.weight(.medium))
                            .foregroundStyle(Color.textInverse)
                            .frame(width: 18, height: 18)
                            .background(Color.accent)
                            .clipShape(Circle())

                        Text(character.name)
                            .font(.bodySmall)
                            .foregroundStyle(Color.text1)

                        if let voiceStyle = character.voiceStyle, !voiceStyle.isEmpty {
                            Spacer()
                            TagView(
                                text: voiceStyle,
                                color: Color.text2,
                                bgColor: Color.bg2,
                                size: .small
                            )
                        }
                    }
                }
            }
        }
        .padding(Spacing.xl)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func audioPreviewSection(_ storyboard: Storyboard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionTitle("音频预览")

            if let audioUrl = storyboard.ttsAudioUrl, !audioUrl.isEmpty {
                AudioPlayerView(urlString: audioUrl)
            } else {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "speaker.slash")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Color.text3)

                    Text("尚未生成配音")
                        .font(.bodySmall)
                        .foregroundStyle(Color.text3)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.xl)
                .background(Color.bg2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
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

    /// 是否有对白分镜可显示。
    private var hasResults: Bool {
        !dialogueStoryboards.isEmpty
    }

    /// 含有对话的分镜列表。
    private var dialogueStoryboards: [Storyboard] {
        viewModel.storyboards.filter { storyboard in
            guard let dialogue = storyboard.dialogue else { return false }
            return !dialogue.isEmpty
        }
    }

    /// 未生成配音的分镜列表。
    private var pendingStoryboards: [Storyboard] {
        dialogueStoryboards.filter { $0.ttsAudioUrl == nil || $0.ttsAudioUrl!.isEmpty }
    }

    /// 生成单个分镜配音。
    private func generateDubbing(_ storyboard: Storyboard) {
        // TODO: 调用 TTS 配音生成 API
        // Task { await viewModel.generateDubbing(storyboardId: storyboard.id) }
    }

    /// 批量生成所有待配音的分镜。
    private func batchGenerate() {
        isBatchGenerating = true
        // TODO: 调用批量 TTS 配音生成 API
        // Task {
        //     await viewModel.batchGenerateDubbing()
        //     isBatchGenerating = false
        // }

        // 模拟延时后恢复（待 API 接入后移除）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isBatchGenerating = false
        }
    }
}
