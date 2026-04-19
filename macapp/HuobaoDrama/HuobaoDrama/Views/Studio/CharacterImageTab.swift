import SwiftUI

// MARK: - CharacterImageTab

/// 角色形象生成标签页。
/// 展示角色列表，支持单个和批量生成角色形象图片。
struct CharacterImageTab: View {
    @ObservedObject var viewModel: StudioViewModel

    /// 当前选中查看详情的角色 ID。
    @State private var selectedCharacterId: Int? = nil

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
                let completed = viewModel.characters.filter { $0.imageUrl != nil && !$0.imageUrl!.isEmpty }.count
                Text("\(viewModel.characters.count) 角色")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text2)
                Text("\u{00B7}")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text3)
                Text("已完成 \(completed)/\(viewModel.characters.count)")
                    .font(.labelMedium)
                    .foregroundStyle(completed == viewModel.characters.count ? Color.statusSuccess : Color.text2)
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
                .disabled(pendingCharacters.isEmpty)
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

            Image(systemName: "person.crop.rectangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.text3)
                .frame(width: 64, height: 64)
                .background(Color.bg2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

            Text("暂无角色数据")
                .font(.headingLarge)
                .foregroundStyle(Color.text1)

            Text("请先在剧本管线中完成角色提取步骤，再进行角色形象生成。")
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

            Text("正在批量生成角色形象...")
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

    // MARK: - 结果视图（左右分栏）

    private var resultsView: some View {
        HStack(spacing: 0) {
            // 左侧：角色列表
            characterList

            Divider()

            // 右侧：角色详情 / 图片预览
            detailPanel
        }
        .background(Color.bg1)
    }

    // MARK: - 角色列表

    private var characterList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xs) {
                ForEach(viewModel.characters) { character in
                    characterListItem(character)
                }
            }
            .padding(Spacing.sm)
        }
        .frame(width: 300)
        .background(Color.bgCard)
    }

    private func characterListItem(_ character: Character) -> some View {
        let isSelected = selectedCharacterId == character.id
        let hasImage = character.imageUrl != nil && !character.imageUrl!.isEmpty

        return Button {
            selectedCharacterId = character.id
        } label: {
            HStack(spacing: Spacing.md) {
                // 头像
                Text(String(character.name.prefix(1)))
                    .font(.bodyLarge.weight(.semibold))
                    .foregroundStyle(Color.textInverse)
                    .frame(width: 32, height: 32)
                    .background(Color.accent)
                    .clipShape(Circle())

                // 信息
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(character.name)
                        .font(.bodyMedium.weight(.medium))
                        .foregroundStyle(isSelected ? Color.textInverse : Color.text0)
                        .lineLimit(1)

                    if let desc = character.description, !desc.isEmpty {
                        Text(desc)
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

    private var selectedCharacter: Character? {
        guard let id = selectedCharacterId else { return nil }
        return viewModel.characters.first(where: { $0.id == id })
    }

    private var detailPanel: some View {
        Group {
            if let character = selectedCharacter {
                characterDetailView(character)
            } else {
                noSelectionView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSelectionView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "person.crop.rectangle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.text3)

            Text("选择一个角色查看详情")
                .font(.bodyMedium)
                .foregroundStyle(Color.text3)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func characterDetailView(_ character: Character) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // 标题行
                detailHeader(character)

                // 角色信息卡片
                characterInfoCard(character)

                // 图片预览区域
                imagePreviewSection(character)
            }
            .padding(Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg1)
    }

    private func detailHeader(_ character: Character) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(character.name)
                    .font(.displaySmall)
                    .foregroundStyle(Color.text0)

                if let role = character.role, !role.isEmpty {
                    TagView(text: role, size: .small)
                }
            }

            Spacer()

            // 单个生成按钮
            let hasImage = character.imageUrl != nil && !character.imageUrl!.isEmpty
            Button {
                generateCharacterImage(character)
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: hasImage ? "arrow.clockwise" : "wand.and.stars")
                        .font(.system(size: IconSize.xs, weight: .medium))
                    Text(hasImage ? "重新生成" : "生成形象")
                        .font(.bodySmall.weight(.medium))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func characterInfoCard(_ character: Character) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionTitle("角色信息")

            if let appearance = character.appearance, !appearance.isEmpty {
                infoRow(label: "外貌", value: appearance)
            }
            if let personality = character.personality, !personality.isEmpty {
                infoRow(label: "性格", value: personality)
            }
            if let description = character.description, !description.isEmpty {
                infoRow(label: "描述", value: description)
            }
        }
        .padding(Spacing.xl)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func imagePreviewSection(_ character: Character) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionTitle("形象图片")

            if let imageUrl = character.imageUrl, !imageUrl.isEmpty {
                // 显示已生成的图片
                InlineAsyncImage(urlString: imageUrl, aspectRatio: 3 / 4)
                    .frame(maxWidth: 320, maxHeight: 440)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            } else {
                // 未生成图片占位
                VStack(spacing: Spacing.md) {
                    Image(systemName: "photo")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.text3)
                        .frame(width: 200, height: 260)
                        .background(Color.bg2)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

                    Text("尚未生成形象图片")
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

    private func infoRow(label: String, value: String) -> some View {
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

    /// 是否有角色结果可显示。
    private var hasResults: Bool {
        !viewModel.characters.isEmpty
    }

    /// 未生成形象图片的角色列表。
    private var pendingCharacters: [Character] {
        viewModel.characters.filter { $0.imageUrl == nil || $0.imageUrl!.isEmpty }
    }

    /// 生成单个角色形象。
    private func generateCharacterImage(_ character: Character) {
        // TODO: 调用角色形象生成 API
        // Task { await viewModel.generateCharacterImage(characterId: character.id) }
    }

    /// 批量生成所有待生成的角色形象。
    private func batchGenerate() {
        isBatchGenerating = true
        // TODO: 调用批量角色形象生成 API
        // Task {
        //     await viewModel.batchGenerateCharacterImages()
        //     isBatchGenerating = false
        // }

        // 模拟延时后恢复（待 API 接入后移除）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isBatchGenerating = false
        }
    }
}
