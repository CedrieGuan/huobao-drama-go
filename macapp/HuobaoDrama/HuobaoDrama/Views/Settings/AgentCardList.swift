import SwiftUI

// MARK: - D6.1 + D6.2  Agent card list with expand/collapse, editing and save

struct AgentCardList: View {
    let viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            // Section header
            sectionHeader("Agent 配置", "调整模型、提示词和参数，保存后立即生效。")

            if viewModel.agentConfigs.isEmpty && viewModel.textModelOptions.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                agentCards
            }
        }
    }

    // MARK: - Agent Cards

    private var agentCards: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(SettingsViewModel.agentDefs, id: \.type) { def in
                agentCard(def)
            }
        }
    }

    private func agentCard(_ def: AgentDef) -> some View {
        let isExpanded = viewModel.expandedAgentType == def.type

        return VStack(spacing: 0) {
            // Header row (always visible, clickable)
            Button {
                viewModel.toggleAgentExpand(def.type)
            } label: {
                HStack(spacing: Spacing.md) {
                    // Icon badge
                    agentBadge(def)

                    // Name + type
                    VStack(alignment: .leading, spacing: 2) {
                        Text(def.label)
                            .font(.labelMedium)
                            .foregroundStyle(Color.text0)
                        Text(def.type)
                            .font(.monoSmall)
                            .foregroundStyle(Color.text3)
                    }

                    Spacer()

                    // Status tag
                    if viewModel.agentConfig(forType: def.type) != nil {
                        TagView(
                            text: "已配置",
                            color: Color.statusSuccess,
                            bgColor: Color.statusSuccessLight,
                            size: .small
                        )
                    } else {
                        TagView(
                            text: "默认",
                            color: Color.text2,
                            bgColor: Color.bg2,
                            size: .small
                        )
                    }

                    // Chevron
                    Image(systemName: "chevron.down")
                        .font(.system(size: IconSize.xs, weight: .medium))
                        .foregroundStyle(Color.text3)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(Animation.normal, value: isExpanded)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded body — edit form (D6.2)
            if isExpanded {
                Divider().padding(.horizontal, Spacing.lg)

                AgentEditForm(viewModel: viewModel, agentType: def.type)
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

    // MARK: - Badge

    private func agentBadge(_ def: AgentDef) -> some View {
        Image(systemName: def.icon)
            .font(.system(size: IconSize.sm))
            .foregroundStyle(Color.accent)
            .frame(width: 36, height: 36)
            .background(Color.accentLight)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 28))
                .foregroundStyle(Color.text3)
            Text("暂无 Agent 配置")
                .font(.headingSmall)
                .foregroundStyle(Color.text1)
            Text("请先通过「AI 服务配置」创建文本服务配置，然后使用火宝一键配置初始化 Agent 默认参数。")
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

    // MARK: - Section Header

    private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.displaySmall)
                .foregroundStyle(Color.text0)
            Text(subtitle)
                .font(.bodySmall)
                .foregroundStyle(Color.text2)
        }
    }
}

// MARK: - D6.2  Agent Edit Form (inline in expanded card)

private struct AgentEditForm: View {
    @ObservedObject var viewModel: SettingsViewModel
    let agentType: String

    // Form state — initialized from existing config or defaults on appear
    @State private var model: String? = nil
    @State private var temperature: Double = 0.7
    @State private var maxTokens: Int = 4096
    @State private var systemPrompt: String = ""

    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showSaved = false
    @State private var initialized = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Model selector
            modelField

            // Temperature + Max Tokens row
            HStack(spacing: Spacing.xl) {
                temperatureField
                maxTokensField
            }

            // System prompt
            promptField

            // Action bar
            actionBar
        }
        .onAppear { populateFields() }
    }

    // MARK: - Model Selector

    private var modelField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Text("模型")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text1)
                Text("(留空使用 AI 服务默认)")
                    .font(.labelSmall)
                    .foregroundStyle(Color.text3)
            }
            SearchablePicker(
                placeholder: "— 使用 AI 服务默认 —",
                options: viewModel.textModelOptions,
                selectedValue: Binding(
                    get: { model },
                    set: { model = $0 }
                )
            )
        }
    }

    // MARK: - Temperature

    private var temperatureField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Temperature")
                .font(.labelMedium)
                .foregroundStyle(Color.text1)
            HStack(spacing: Spacing.md) {
                Slider(value: $temperature, in: 0...2, step: 0.1)
                    .tint(Color.accent)
                Text(String(format: "%.1f", temperature))
                    .font(.monoSmall)
                    .foregroundStyle(Color.text1)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }

    // MARK: - Max Tokens

    private var maxTokensField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Max Tokens")
                .font(.labelMedium)
                .foregroundStyle(Color.text1)
            TextField("4096", value: $maxTokens, format: .number)
                .textFieldStyle(AppTextFieldStyle())
                .frame(width: 100)
        }
    }

    // MARK: - System Prompt

    private var promptField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("System Prompt")
                .font(.labelMedium)
                .foregroundStyle(Color.text1)
            ZStack(alignment: .topLeading) {
                // Placeholder
                if systemPrompt.isEmpty {
                    Text("Agent 系统提示词...")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.text3)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.md)
                }
                TextEditor(text: $systemPrompt)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.text0)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.xs)
                    .frame(minHeight: 160)
            }
            .background(Color.bg1)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.border0, lineWidth: 1))
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: Spacing.sm) {
            // Reset prompt button
            Button("恢复默认提示词") {
                systemPrompt = SettingsViewModel.defaultPrompt(forAgent: agentType)
            }
            .buttonStyle(GhostButtonStyle())

            // Saved indicator
            if showSaved {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark")
                        .font(.system(size: IconSize.xs))
                    Text("已保存")
                        .font(.labelSmall)
                }
                .foregroundStyle(Color.statusSuccess)
                .transition(.opacity)
            }

            Spacer()

            // Save button
            Button {
                Task { await performSave() }
            } label: {
                HStack(spacing: Spacing.xs) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("保存")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isSaving)
        }
    }

    // MARK: - Populate

    private func populateFields() {
        guard !initialized else { return }
        initialized = true

        let cfg = viewModel.agentConfig(forType: agentType)
        model = cfg?.model
        temperature = cfg?.temperature ?? 0.7
        maxTokens = cfg?.maxTokens ?? 4096
        systemPrompt = cfg?.systemPrompt ?? SettingsViewModel.defaultPrompt(forAgent: agentType)
    }

    // MARK: - Save

    private func performSave() async {
        isSaving = true
        saveError = nil
        showSaved = false

        do {
            try await viewModel.saveAgentConfig(
                agentType: agentType,
                model: model,
                temperature: temperature,
                maxTokens: maxTokens,
                systemPrompt: systemPrompt
            )
            withAnimation { showSaved = true }
            // Auto-hide after 3 seconds
            try? await Task.sleep(for: .seconds(3))
            withAnimation { showSaved = false }
        } catch {
            saveError = error.localizedDescription
        }

        isSaving = false
    }
}
