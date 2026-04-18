import SwiftUI

struct DramaDetailPage: View {
    let dramaId: Int
    @State private var viewModel: DramaDetailViewModel
    @Environment(Router.self) private var router

    @State private var showAddDialog = false
    @State private var formTitle = ""
    @State private var formImageConfigId: String?
    @State private var formVideoConfigId: String?
    @State private var formAudioConfigId: String?
    @State private var showError = false
    @State private var showSuccess = false

    private var canConfirm: Bool {
        formImageConfigId != nil && formVideoConfigId != nil && formAudioConfigId != nil
    }

    init(dramaId: Int) {
        self.dramaId = dramaId
        self._viewModel = State(initialValue: DramaDetailViewModel(dramaId: dramaId))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(Color.bg1)
        .task { await viewModel.load() }
        .appSheet(
            isPresented: $showAddDialog,
            title: "创建新集",
            subtitle: "为这一集预先锁定图片、视频和音频生成服务",
            maxWidth: 600,
            onConfirm: { Task { await submitAddEpisode() } },
            confirmTitle: "创建并锁定配置",
            confirmDisabled: !canConfirm,
            isLoading: viewModel.isCreating
        ) {
            addEpisodeForm
        }
        .alert("创建失败", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "未知错误")
        }
        .alert("已添加新集", isPresented: $showSuccess) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("新集已创建，配置已锁定。")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            HStack(alignment: .top, spacing: Spacing.md) {
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

                if let drama = viewModel.drama {
                    metaInfo(drama)
                }
            }

            Spacer()

            if viewModel.drama != nil {
                Button {
                    formTitle = ""
                    formImageConfigId = nil
                    formVideoConfigId = nil
                    formAudioConfigId = nil
                    showAddDialog = true
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus")
                            .font(.system(size: IconSize.xs, weight: .semibold))
                        Text("添加集")
                            .font(.bodyMedium.weight(.medium))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, Spacing.xxxl)
        .padding(.top, Spacing.xxl)
        .padding(.bottom, Spacing.lg)
    }

    private func metaInfo(_ drama: Drama) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(drama.title)
                .font(.displayMedium)
                .foregroundStyle(Color.text0)
            HStack(spacing: Spacing.sm) {
                if let style = drama.style, !style.isEmpty {
                    Text(style)
                        .font(.labelSmall)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Color.accentLight)
                        .foregroundStyle(Color.accent)
                        .clipShape(Capsule())
                }
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "person")
                        .font(.system(size: 10))
                    Text("\(drama.characters.count) 角色")
                        .font(.bodySmall)
                }
                .foregroundStyle(Color.text2)

                HStack(spacing: Spacing.xs) {
                    Image(systemName: "rectangle.grid.1x2")
                        .font(.system(size: 10))
                    Text("\(drama.scenes.count) 场景")
                        .font(.bodySmall)
                }
                .foregroundStyle(Color.text2)
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if let drama = viewModel.drama {
                episodeList(drama)
            }
        }
        .padding(.horizontal, Spacing.xxxl)
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            headerSkeleton
            ForEach(0..<3, id: \.self) { _ in
                episodeCardSkeleton
            }
        }
        .padding(.vertical, Spacing.lg)
    }

    private var headerSkeleton: some View {
        HStack(spacing: Spacing.sm) {
            RoundedRectangle(cornerRadius: Radius.sm).fill(Color.bg3).frame(width: 14, height: 14)
            Text("剧集列表")
                .font(.labelSmall.weight(.bold))
                .foregroundStyle(Color.text3)
        }
    }

    private var episodeCardSkeleton: some View {
        HStack(spacing: Spacing.lg) {
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color.bg2)
                .frame(width: 44, height: 44)
                .shimmer(isActive: true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                RoundedRectangle(cornerRadius: Radius.sm).fill(Color.bg3).frame(width: 120, height: 14)
                RoundedRectangle(cornerRadius: Radius.sm).fill(Color.bg3).frame(width: 80, height: 10)
            }
            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .cardShadow()
    }

    // MARK: - Episode List

    private func episodeList(_ drama: Drama) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "film")
                        .font(.system(size: IconSize.xs))
                    Text("剧集列表")
                        .font(.labelSmall.weight(.bold))
                }
                .foregroundStyle(Color.text3)

                if drama.episodes.isEmpty {
                    episodeEmptyState
                } else {
                    ForEach(drama.episodes) { episode in
                        episodeRow(episode)
                    }
                }
            }
            .padding(.vertical, Spacing.lg)
        }
    }

    private func episodeRow(_ episode: Episode) -> some View {
        Button {
            router.navigate(to: .studio(episodeId: episode.id, dramaId: dramaId))
        } label: {
            HStack(spacing: Spacing.lg) {
                Text(episode.episodeLabel)
                    .font(.monoMedium.weight(.bold))
                    .foregroundStyle(Color.text2)
                    .frame(width: 44, height: 44)
                    .background(Color.bg2)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Color.border0, lineWidth: 1))

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(episode.title)
                        .font(.bodyMedium.weight(.semibold))
                        .foregroundStyle(Color.text0)
                    HStack(spacing: Spacing.sm) {
                        StatusDot(
                            status: hasScript(episode) ? "completed" : "draft",
                            size: 6
                        )
                        Text(hasScript(episode) ? "已完成剧本" : "待编写")
                            .font(.labelSmall)
                            .foregroundStyle(Color.text3)
                        if episode.duration > 0 {
                            Text("\(episode.duration)s")
                                .font(.monoSmall)
                                .foregroundStyle(Color.text3)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: IconSize.sm, weight: .medium))
                    .foregroundStyle(Color.text3)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .cardShadow()
        }
        .buttonStyle(.plain)
    }

    private func hasScript(_ episode: Episode) -> Bool {
        guard let content = episode.scriptContent, !content.isEmpty else { return false }
        return true
    }

    private var episodeEmptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "plus.circle")
                .font(.system(size: IconSize.xl))
                .foregroundStyle(Color.text3)
            Text("点击上方「添加集」创建第一集")
                .font(.bodySmall)
                .foregroundStyle(Color.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.section)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundStyle(Color.border0)
        )
    }

    // MARK: - Add Episode Form

    private var addEpisodeForm: some View {
        VStack(spacing: Spacing.xl) {
            // Section: Basic Info
            VStack(alignment: .leading, spacing: Spacing.md) {
                sectionHeader("基础信息", hint: "只影响显示名称，不影响生成配置")

                field("标题") {
                    TextField("默认按集数自动命名", text: $formTitle)
                        .textFieldStyle(AppTextFieldStyle())
                }

                Text("留空时会自动按集数命名，例如 \"第 3 集\"")
                    .font(.labelSmall)
                    .foregroundStyle(Color.text3)
            }
            .padding(Spacing.md)
            .background(Color.bg1)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Color.border0, lineWidth: 1))

            // Section: Generation Config
            VStack(alignment: .leading, spacing: Spacing.md) {
                sectionHeader("生成配置", hint: "创建后不可更改，建议一次性选对")

                HStack(spacing: Spacing.md) {
                    configPicker(
                        kicker: "IMAGE",
                        label: "图片配置",
                        placeholder: "选择图片服务",
                        configs: viewModel.imageConfigs,
                        selectedId: $formImageConfigId
                    )
                    configPicker(
                        kicker: "VIDEO",
                        label: "视频配置",
                        placeholder: "选择视频服务",
                        configs: viewModel.videoConfigs,
                        selectedId: $formVideoConfigId
                    )
                    configPicker(
                        kicker: "AUDIO",
                        label: "音频配置",
                        placeholder: "选择音频服务",
                        configs: viewModel.audioConfigs,
                        selectedId: $formAudioConfigId
                    )
                }
            }
            .padding(Spacing.md)
            .background(Color.bg1)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Color.border0, lineWidth: 1))

            // Footer hint
            Text("创建后，工作台中的图片、视频、音频生成入口都会锁定到当前集。")
                .font(.labelSmall)
                .foregroundStyle(Color.text3)
        }
    }

    private func sectionHeader(_ title: String, hint: String) -> some View {
        HStack {
            Text(title)
                .font(.headingSmall)
                .foregroundStyle(Color.text0)
            Spacer()
            Text(hint)
                .font(.labelSmall)
                .foregroundStyle(Color.text3)
        }
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(.labelMedium)
                .foregroundStyle(Color.text1)
            content()
        }
    }

    private func configPicker(
        kicker: String,
        label: String,
        placeholder: String,
        configs: [AIServiceConfig],
        selectedId: Binding<String?>
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(kicker)
                .font(.labelSmall)
                .foregroundStyle(Color.text3)
                .textCase(.uppercase)
            Text(label)
                .font(.labelMedium)
                .foregroundStyle(Color.text1)

            SearchablePicker(
                placeholder: placeholder,
                options: configs.map { config in
                    let modelName = config.model.first ?? ""
                    let detail = modelName.isEmpty
                        ? "\(config.name) (\(config.provider ?? ""))"
                        : "\(config.name) · \(modelName) (\(config.provider ?? ""))"
                    return PickerOption(
                        id: String(config.id),
                        label: detail,
                        value: String(config.id)
                    )
                },
                selectedValue: selectedId
            )
        }
    }

    // MARK: - Submit

    private func submitAddEpisode() async {
        guard let imgId = formImageConfigId,
              let vidId = formVideoConfigId,
              let audId = formAudioConfigId else { return }
        let title = formTitle.trimmingCharacters(in: .whitespaces).isEmpty ? nil : formTitle
        let ok = await viewModel.addEpisode(
            title: title,
            imageConfigId: Int(imgId) ?? 0,
            videoConfigId: Int(vidId) ?? 0,
            audioConfigId: Int(audId) ?? 0
        )
        if ok {
            showAddDialog = false
            showSuccess = true
        } else {
            showError = true
        }
    }
}
