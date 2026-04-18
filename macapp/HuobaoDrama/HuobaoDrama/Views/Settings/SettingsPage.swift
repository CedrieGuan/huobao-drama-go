import SwiftUI

struct SettingsPage: View {
    @State private var viewModel = SettingsViewModel()
    @State private var testingConfigId: Int?
    @State private var configToDelete: AIServiceConfig?

    // Edit sheet state (D4.1 + D4.2)
    @State private var showEditSheet = false
    @State private var editSheetMode: AIConfigEditSheet.Mode?

    // Huobao preset sheet state (D5.1)
    @State private var showHuobaoPreset = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            contentArea
        }
        .background(Color.bg0)
        .task { await viewModel.load() }
        .overlay {
            if showEditSheet, let mode = editSheetMode {
                ZStack {
                    Color.bgOverlay.ignoresSafeArea()
                        .onTapGesture {
                            showEditSheet = false
                            editSheetMode = nil
                        }
                    editSheetContainer(mode: mode)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(999)
            } else if showHuobaoPreset {
                ZStack {
                    Color.bgOverlay.ignoresSafeArea()
                        .onTapGesture { showHuobaoPreset = false }
                    HuobaoPresetSheet(
                        viewModel: viewModel,
                        onConfirm: {
                            showHuobaoPreset = false
                        },
                        onCancel: {
                            showHuobaoPreset = false
                        }
                    )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(999)
            }
        }
        .animation(Animation.normal, value: showEditSheet)
        .animation(Animation.normal, value: showHuobaoPreset)
        .alert(
            "删除配置",
            isPresented: Binding(
                get: { configToDelete != nil },
                set: { if !$0 { configToDelete = nil } }
            )
        ) {
            Button("取消", role: .cancel) { configToDelete = nil }
            Button("删除", role: .destructive) {
                if let c = configToDelete {
                    Task { await viewModel.deleteConfig(c) }
                    configToDelete = nil
                }
            }
        } message: {
            if let c = configToDelete {
                Text("确定删除「\(c.name)」？")
            }
        }
        // Toast overlay for preset creation results
        .overlay(alignment: .top) {
            if let toast = viewModel.presetToast {
                ToastBanner(toast: toast) {
                    withAnimation(Animation.normal) {
                        viewModel.presetToast = nil
                    }
                }
                .padding(.top, Spacing.lg)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Animation.normal, value: viewModel.presetToast)
    }

    // MARK: - Edit Sheet Container

    @ViewBuilder
    private func editSheetContainer(mode: AIConfigEditSheet.Mode) -> some View {
        ModalSheet(
            title: mode.isCreate
                ? "添加\(SettingsViewModel.serviceTypes.first { $0.type == mode.serviceType }?.label ?? "")服务"
                : "编辑服务配置",
            subtitle: "推荐先选择模板，系统会自动填入更合理的 Base URL 与默认模型。",
            isPresented: $showEditSheet,
            maxWidth: 580,
            onConfirm: nil,
            content: {
                AIConfigEditSheet(
                    mode: mode,
                    onSave: {
                        showEditSheet = false
                        editSheetMode = nil
                        Task { await viewModel.load() }
                    },
                    onCancel: {
                        showEditSheet = false
                        editSheetMode = nil
                    }
                )
            }
        )
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Base tabs
            VStack(alignment: .leading, spacing: Spacing.xs) {
                sidebarLabel("基础")
                ForEach(viewModel.baseTabs, id: \.self) { tab in
                    navButton(tab)
                }
            }
            .padding(.horizontal, Spacing.lg)

            Spacer()

            // Advanced toggle
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Toggle(isOn: $viewModel.showAdvanced) {
                    Text("Agent 高级配置")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.text1)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Text("仅展开 Agent 配置与 Skills")
                    .font(.labelSmall)
                    .foregroundStyle(Color.text3)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.lg)

            // Advanced tabs
            if viewModel.showAdvanced {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    sidebarLabel("高级")
                    ForEach(viewModel.advancedTabs, id: \.self) { tab in
                        navButton(tab)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xl)
                .transition(.opacity)
            }
        }
        .padding(.top, Spacing.xxl)
        .frame(width: 200)
        .background(Color.bg1)
    }

    private func sidebarLabel(_ text: String) -> some View {
        Text(text)
            .font(.labelSmall)
            .foregroundStyle(Color.text3)
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, Spacing.xs)
    }

    private func navButton(_ tab: SettingsTab) -> some View {
        let isSelected = viewModel.selectedTab == tab
        return Button {
            viewModel.selectedTab = tab
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: tab.icon)
                    .font(.system(size: IconSize.xs))
                Text(tab.label)
                    .font(.bodyMedium)
            }
            .foregroundStyle(isSelected ? Color.accent : Color.text1)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentLight : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content Area

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                switch viewModel.selectedTab {
                case .ai:
                    aiSectionPlaceholder
                case .agents:
                    AgentCardList(viewModel: viewModel)
                case .skills:
                    skillsSectionPlaceholder
                }
            }
            .padding(Spacing.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.bg0)
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.displaySmall)
                .foregroundStyle(Color.text0)
            Text(subtitle)
                .font(.bodySmall)
                .foregroundStyle(Color.text2)
        }
    }

    private var aiSectionPlaceholder: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            // Brand header
            brandHeader

            // Section title
            sectionHeader("AI 服务配置", subtitle: "用推荐模板快速落配置，再按服务类型微调。工作台创建集时会锁定所选图片、视频和音频能力。")

            // Huobao preset panel
            huobaoPresetPanel

            // Quick templates
            quickTemplatePanel

            // Service type sections with config rows
            ForEach(SettingsViewModel.serviceTypes, id: \.type) { st in
                serviceSection(st)
            }
        }
    }

    // MARK: - Brand

    private var brandHeader: some View {
        HStack(spacing: Spacing.md) {
            Text("火")
                .font(.displayMedium)
                .foregroundStyle(Color.accent)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.bgCard)
                        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("HUOBAO SHORTS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.text3)
                    .tracking(1.4)
                Text("火宝短剧")
                    .font(.headingLarge)
                    .foregroundStyle(Color.text1)
            }
        }
    }

    // MARK: - Preset Panel

    private var huobaoPresetPanel: some View {
        CardView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("QUICK SETUP")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(Color.text3)
                        Text("火宝推荐配置")
                            .font(.headingMedium)
                            .foregroundStyle(Color.text0)
                        Text("一键写入文本、图片、视频、音频四类推荐配置，适合作为开箱默认方案。")
                            .font(.bodySmall)
                            .foregroundStyle(Color.text2)
                    }
                    Spacer()
                    Button {
                        showHuobaoPreset = true
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "sparkles")
                                .font(.system(size: IconSize.xs))
                            Text("火宝一键配置")
                                .font(.bodyMedium.weight(.medium))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }

                // Preset cards grid
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm
                ) {
                    ForEach(SettingsViewModel.huobaoPresetCards, id: \.serviceType) { card in
                        presetCard(card)
                    }
                }
            }
        }
    }

    private func presetCard(_ card: PresetCard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(card.label)
                    .font(.labelMedium)
                    .foregroundStyle(Color.text0)
                Spacer()
                TagView(
                    text: card.provider, color: Color.accent, bgColor: Color.accentLight,
                    size: .small)
            }
            Text(card.model)
                .font(.monoSmall)
                .foregroundStyle(Color.text1)
            Text(card.baseUrl)
                .font(.monoSmall)
                .foregroundStyle(Color.text3)
                .lineLimit(1)
        }
        .padding(Spacing.md)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Color.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Color.border0, lineWidth: 1))
    }

    // MARK: - Quick Templates

    private var quickTemplatePanel: some View {
        CardView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("快捷模板")
                        .font(.headingMedium)
                        .foregroundStyle(Color.text0)
                    Text("选择服务类型后，直接用模板填充推荐的 provider / base URL / model。")
                        .font(.bodySmall)
                        .foregroundStyle(Color.text2)
                }
                HStack(spacing: Spacing.sm) {
                    ForEach(SettingsViewModel.serviceTypes, id: \.type) { st in
                        Button {
                            editSheetMode = .create(serviceType: st.type)
                            showEditSheet = true
                        } label: {
                            Text(st.label)
                                .font(.bodyMedium)
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: - Service Section

    private func serviceSection(_ st: ServiceTypeMeta) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Section header
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(st.label)
                        .font(.headingSmall)
                        .foregroundStyle(Color.text0)
                    Text(st.description)
                        .font(.labelSmall)
                        .foregroundStyle(Color.text3)
                }
                let count = viewModel.countActive(st.type)
                if count > 0 {
                    TagView(
                        text: "\(count) 已启用", color: Color.accent, bgColor: Color.accentLight,
                        size: .small)
                }
                Spacer()
                Button {
                    editSheetMode = .create(serviceType: st.type)
                    showEditSheet = true
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                        Text("添加")
                            .font(.bodySmall)
                    }
                }
                .buttonStyle(GhostButtonStyle())
            }

            // Config rows
            let configs = viewModel.configsByType(st.type)
            if configs.isEmpty {
                Text("暂无配置")
                    .font(.bodySmall)
                    .foregroundStyle(Color.text3)
                    .padding(.vertical, Spacing.sm)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(configs) { config in
                        configRow(config)
                    }
                }
            }
        }
    }

    private func configRow(_ config: AIServiceConfig) -> some View {
        HStack(spacing: Spacing.md) {
            // Info
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Text(config.provider ?? "—")
                        .font(.labelMedium)
                        .foregroundStyle(Color.text0)
                    Text(config.name)
                        .font(.labelSmall)
                        .foregroundStyle(Color.text2)
                }
                Text(config.model.joined(separator: ", "))
                    .font(.monoSmall)
                    .foregroundStyle(Color.text2)
                    .lineLimit(1)
                Text(config.baseUrl)
                    .font(.monoSmall)
                    .foregroundStyle(Color.text3)
                    .lineLimit(1)
            }

            Spacer()

            // API Key status
            TagView(
                text: config.apiKey.isEmpty ? "无密钥" : "已配置",
                color: config.apiKey.isEmpty ? Color.statusError : Color.statusSuccess,
                bgColor: config.apiKey.isEmpty ? Color.statusErrorLight : Color.statusSuccessLight,
                size: .small
            )

            // Test
            Button {
                Task {
                    testingConfigId = config.id
                    _ = await viewModel.testConfig(config)
                    testingConfigId = nil
                }
            } label: {
                if testingConfigId == config.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("测试")
                        .font(.bodySmall)
                }
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(testingConfigId != nil)

            // Toggle
            Toggle(
                "",
                isOn: Binding(
                    get: { config.isActive },
                    set: { _ in Task { await viewModel.toggleConfig(config) } }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()

            // Edit
            Button {
                editSheetMode = .edit(config)
                showEditSheet = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: IconSize.xs))
            }
            .buttonStyle(IconButtonStyle())

            // Delete
            Button {
                configToDelete = config
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: IconSize.xs))
            }
            .buttonStyle(IconButtonStyle())
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Color.border0, lineWidth: 1))
    }

    private var skillsSectionPlaceholder: some View {
        sectionHeader("Skills 管理", subtitle: "Skills 仅作为 Agent 的高级提示词层使用。")
    }
}

// MARK: - SettingsTab Extensions

extension SettingsTab {
    var label: String {
        switch self {
        case .ai: return "AI 服务"
        case .agents: return "Agent"
        case .skills: return "Skills"
        }
    }

    var icon: String {
        switch self {
        case .ai: return "cpu"
        case .agents: return "brain"
        case .skills: return "doc.text"
        }
    }
}
