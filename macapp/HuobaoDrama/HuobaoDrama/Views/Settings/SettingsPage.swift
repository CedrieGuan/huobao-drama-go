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

    // Skill delete confirmation state (D7.2)
    @State private var skillToDelete: Skill?

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
        // Skill delete confirmation alert
        .alert(
            "删除 Skill",
            isPresented: Binding(
                get: { skillToDelete != nil },
                set: { if !$0 { skillToDelete = nil } }
            )
        ) {
            Button("取消", role: .cancel) { skillToDelete = nil }
            Button("删除", role: .destructive) {
                if let s = skillToDelete {
                    Task { await viewModel.deleteSkill(s) }
                    skillToDelete = nil
                }
            }
        } message: {
            if let s = skillToDelete {
                Text("确定删除「\(s.name.isEmpty ? s.id : s.name)」？")
            }
        }
        // Toast overlay for operation results
        .overlay(alignment: .top) {
            if let toast = viewModel.toast {
                ToastBanner(toast: toast) {
                    withAnimation(Animation.normal) {
                        viewModel.toast = nil
                    }
                }
                .padding(.top, Spacing.lg)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Animation.normal, value: viewModel.toast)
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
        HStack(alignment: .top, spacing: Spacing.lg) {
            // MARK: - Left sidebar: Agent list
            agentSidebar

            Divider()

            // MARK: - Right main content
            skillsMainContent
        }
        .appSheet(
            isPresented: $viewModel.showAddSkillSheet,
            title: "新增 Skill",
            subtitle: "为 \(agentLabel(viewModel.selectedAgentType)) 创建新的提示词文件。",
            maxWidth: 460,
            onConfirm: {
                Task { await viewModel.confirmAddSkill() }
            },
            confirmTitle: "创建",
            confirmDisabled: viewModel.newSkillId.trimmingCharacters(in: .whitespaces).isEmpty
                || viewModel.newSkillName.trimmingCharacters(in: .whitespaces).isEmpty
                || viewModel.isCreatingSkill,
            isLoading: viewModel.isCreatingSkill,
            content: { addSkillForm }
        )
    }

    // MARK: - Agent Sidebar

    private var agentSidebar: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(SettingsViewModel.agentDefs, id: \.type) { def in
                agentSidebarButton(def)
            }
        }
        .frame(width: 180, alignment: .leading)
    }

    private func agentSidebarButton(_ def: AgentDef) -> some View {
        let isSelected = viewModel.selectedAgentType == def.type
        let count = viewModel.agentSkillCount(def.type)

        return Button {
            viewModel.selectAgent(def.type)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: def.icon)
                    .font(.system(size: IconSize.sm))
                    .foregroundStyle(isSelected ? Color.accent : Color.text2)
                    .frame(width: 28, height: 28)
                    .background(isSelected ? Color.accentLight : Color.bg2)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

                Text(def.label)
                    .font(.bodyMedium)
                    .foregroundStyle(isSelected ? Color.text0 : Color.text1)
                    .lineLimit(1)

                Spacer()

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accent : Color.text2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.accentLight : Color.bg2)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentLight.opacity(0.5) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Skills Main Content

    private var skillsMainContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Header
            HStack(spacing: Spacing.md) {
                let def = SettingsViewModel.agentDefs.first { $0.type == viewModel.selectedAgentType }
                if let def = def {
                    Image(systemName: def.icon)
                        .font(.system(size: IconSize.md))
                        .foregroundStyle(Color.accent)
                        .frame(width: 36, height: 36)
                        .background(Color.accentLight)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    Text(def.label)
                        .font(.headingLarge)
                        .foregroundStyle(Color.text0)
                }

                Spacer()

                Button {
                    viewModel.startAddSkill()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus")
                            .font(.system(size: IconSize.xs))
                        Text("新增 Skill")
                            .font(.bodyMedium.weight(.medium))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            // Skills list or empty state
            if viewModel.currentSkills.isEmpty {
                skillsEmptyState
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(viewModel.currentSkills) { skill in
                        skillCard(skill)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Skills Empty State

    private var skillsEmptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "doc.text")
                .font(.system(size: 28))
                .foregroundStyle(Color.text3)
            Text("暂无 Skill")
                .font(.headingSmall)
                .foregroundStyle(Color.text1)
            Text("为当前 Agent 创建 Skill 文件，可自定义高级提示词来增强 Agent 的特定能力。")
                .font(.bodySmall)
                .foregroundStyle(Color.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xxxl)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Color.border0, lineWidth: 1))
    }

    // MARK: - Skill Card

    private func skillCard(_ skill: Skill) -> some View {
        let isEditing = viewModel.editingSkillId == skill.id
        let isDeleting = viewModel.deletingSkillId == skill.id

        return VStack(spacing: 0) {
            // Header (clickable)
            Button {
                Task { await viewModel.toggleSkillEdit(skill) }
            } label: {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(Color.accent)
                        .frame(width: 32, height: 32)
                        .background(Color.accentLight)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name.isEmpty ? skill.id : skill.name)
                            .font(.labelMedium)
                            .foregroundStyle(Color.text0)
                        if !skill.description.isEmpty {
                            Text(skill.description)
                                .font(.labelSmall)
                                .foregroundStyle(Color.text2)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Delete button
                    Button {
                        if isDeleting { return }
                        skillToDelete = skill
                    } label: {
                        if isDeleting {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "trash")
                                .font(.system(size: IconSize.xs))
                        }
                    }
                    .buttonStyle(IconButtonStyle())
                    .disabled(isDeleting)

                    // Chevron
                    Image(systemName: "chevron.down")
                        .font(.system(size: IconSize.xs, weight: .medium))
                        .foregroundStyle(Color.text3)
                        .rotationEffect(.degrees(isEditing ? 180 : 0))
                        .animation(Animation.normal, value: isEditing)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isEditing {
                Divider().padding(.horizontal, Spacing.lg)

                skillEditBody(skill)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Color.border0, lineWidth: 1))
        .cardShadow()
    }

    // MARK: - Skill Edit Body

    private func skillEditBody(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Text editor
            ZStack(alignment: .topLeading) {
                if viewModel.skillContent.isEmpty {
                    Text("Skill 提示词内容...")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.text3)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.md)
                }
                TextEditor(text: $viewModel.skillContent)
                    .font(.monoSmall)
                    .foregroundStyle(Color.text0)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.xs)
                    .frame(minHeight: 200)
            }
            .background(Color.bg1)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.border0, lineWidth: 1))

            // Footer: path hint + save status + button
            HStack(spacing: Spacing.sm) {
                Text("skills/\(skill.id).md")
                    .font(.monoSmall)
                    .foregroundStyle(Color.text3)

                Spacer()

                // Saved indicator
                if viewModel.skillSavedId == skill.id {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark")
                            .font(.system(size: IconSize.xs))
                        Text("已保存")
                            .font(.labelSmall)
                    }
                    .foregroundStyle(Color.statusSuccess)
                }

                // Save button
                Button {
                    Task { await viewModel.saveSkillContent() }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        if viewModel.isSkillSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("保存")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isSkillSaving)
            }
        }
    }

    // MARK: - Add Skill Form

    private var addSkillForm: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // 验证错误提示
            if let validationError = viewModel.skillValidationError {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(Color.statusError)
                    Text(validationError)
                        .font(.bodySmall)
                        .foregroundStyle(Color.statusError)
                }
                .padding(Spacing.md)
                .background(Color.statusErrorLight)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Skill ID")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text1)
                TextField("my_skill", text: $viewModel.newSkillId)
                    .textFieldStyle(AppTextFieldStyle())
                Text("仅支持字母、数字、下划线和中划线")
                    .font(.labelSmall)
                    .foregroundStyle(Color.text3)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("名称")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text1)
                TextField("Skill 名称", text: $viewModel.newSkillName)
                    .textFieldStyle(AppTextFieldStyle())
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("描述")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text1)
                TextField("简要描述用途", text: $viewModel.newSkillDescription)
                    .textFieldStyle(AppTextFieldStyle())
            }
        }
        // 输入变化时清除验证错误
        .onChange(of: viewModel.newSkillId) { _, _ in viewModel.skillValidationError = nil }
        .onChange(of: viewModel.newSkillName) { _, _ in viewModel.skillValidationError = nil }
    }

    // MARK: - Helpers

    private func agentLabel(_ type: String) -> String {
        SettingsViewModel.agentDefs.first { $0.type == type }?.label ?? type
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
