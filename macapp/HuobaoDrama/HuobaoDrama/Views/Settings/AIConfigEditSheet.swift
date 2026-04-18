import SwiftUI

/// AI 服务配置编辑弹窗 — 新增/编辑共用。
///
/// D4.1: 通用表单字段
/// D4.2: 模板填充、provider 前缀提示、保存校验
struct AIConfigEditSheet: View {

    // MARK: - Mode

    enum Mode {
        case create(serviceType: String)
        case edit(AIServiceConfig)

        var isCreate: Bool {
            if case .create = self { return true }
            return false
        }

        var serviceType: String {
            switch self {
            case .create(let st): return st
            case .edit(let config): return config.serviceType
            }
        }
    }

    let mode: Mode
    let onSave: () -> Void
    let onCancel: () -> Void

    init(mode: Mode, onSave: @escaping () -> Void, onCancel: @escaping () -> Void = {}) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel
    }

    // MARK: - Form State

    @State private var name: String = ""
    @State private var provider: String = ""
    @State private var priority: Int = 0
    @State private var apiKey: String = ""
    @State private var baseUrl: String = ""
    @State private var modelText: String = ""  // comma-separated

    @State private var isSaving = false
    @State private var saveError: String?

    // Per-field validation errors
    @State private var nameError: String?
    @State private var apiKeyError: String?
    @State private var baseUrlError: String?
    @State private var modelError: String?

    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    private var serviceType: String {
        switch mode {
        case .create(let st): return st
        case .edit(let config): return config.serviceType
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Service type indicator
            serviceTypeIndicator

            // Template picker (create mode only)
            if isCreate {
                templatePicker
            }

            // Fields
            field("配置名称", error: nameError) {
                TextField("例如：ChatGPT-4o", text: $name)
                    .textFieldStyle(AppTextFieldStyle())
                    .onChange(of: name) { _, _ in clearError(&nameError) }
            }

            field("服务商 (Provider)", error: nil) {
                SearchablePicker(
                    placeholder: "选择服务商",
                    options: providerOptions,
                    selectedValue: Binding(
                        get: { provider.isEmpty ? nil : provider },
                        set: { newValue in
                            provider = newValue ?? ""
                            clearError(&nameError)
                        }
                    )
                )
            }

            field("优先级") {
                Stepper(value: $priority, in: 0...100) {
                    TextField("", value: $priority, format: .number)
                        .textFieldStyle(AppTextFieldStyle())
                        .frame(width: 60)
                }
            }

            field("API Key", error: apiKeyError) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    SecureField(apiKeyPlaceholder, text: $apiKey)
                        .textFieldStyle(AppTextFieldStyle())
                    if !provider.isEmpty, let hint = SettingsViewModel.apiKeyHints[provider] {
                        Text(hint)
                            .font(.labelSmall)
                            .foregroundStyle(Color.text3)
                    }
                }
                .onChange(of: apiKey) { _, _ in clearError(&apiKeyError) }
            }

            field("Base URL", error: baseUrlError) {
                TextField("https://api.openai.com", text: $baseUrl)
                    .textFieldStyle(AppTextFieldStyle())
                    .onChange(of: baseUrl) { _, _ in clearError(&baseUrlError) }
            }

            // Endpoint hint
            endpointHintRow

            field("模型名称", error: modelError) {
                TextField("多个模型用逗号分隔，如 gpt-4o, gpt-4o-mini", text: $modelText)
                    .textFieldStyle(AppTextFieldStyle())
                    .onChange(of: modelText) { _, _ in clearError(&modelError) }
            }

            // Error
            if let saveError {
                Text(saveError)
                    .font(.bodySmall)
                    .foregroundStyle(Color.statusError)
            }

            // Action bar
            actionBar
        }
        .onAppear(perform: populateFields)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: Spacing.sm) {
            Spacer()
            Button("取消") {
                onCancel()
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                Task { await performSave() }
            } label: {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("保存")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isSaving)
        }
        .padding(.top, Spacing.sm)
    }

    // MARK: - Service Type Indicator

    private var serviceTypeIndicator: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(Color.accent)
                .frame(width: 8, height: 8)
            Text(serviceTypeLabel)
                .font(.labelMedium)
                .foregroundStyle(Color.text2)
            Spacer()
            if isCreate {
                Text("新增")
                    .font(.labelSmall)
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.accentLight)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
            }
        }
        .padding(Spacing.sm)
        .background(Color.bg1)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private var serviceTypeLabel: String {
        SettingsViewModel.serviceTypes.first { $0.type == serviceType }?.label ?? serviceType
    }

    // MARK: - Template Picker

    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("快捷模板")
                .font(.labelMedium)
                .foregroundStyle(Color.text1)
            Text("选择模板后自动填充 provider、Base URL 和默认模型。")
                .font(.labelSmall)
                .foregroundStyle(Color.text3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(SettingsViewModel.presetsForType(serviceType)) { preset in
                        Button {
                            applyPreset(preset)
                        } label: {
                            HStack(spacing: Spacing.xs) {
                                Text(preset.label)
                                    .font(.bodyMedium)
                                    .foregroundStyle(provider == preset.provider ? Color.accent : Color.text1)
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(provider == preset.provider ? Color.accentLight : Color.bg1)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.full))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.full)
                                    .stroke(provider == preset.provider ? Color.accent : Color.border0, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Endpoint Hint

    private var endpointHintRow: some View {
        HStack(spacing: Spacing.xs) {
            Text("端点前缀:")
                .font(.labelSmall)
                .foregroundStyle(Color.text3)
            Text(SettingsViewModel.endpointHint(provider: provider, baseUrl: baseUrl))
                .font(.monoSmall)
                .foregroundStyle(Color.text2)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.bg1)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(Color.border0, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    // MARK: - Provider Options

    private var providerOptions: [PickerOption] {
        // Combine preset providers with API-loaded providers
        var seen = Set<String>()
        var options: [PickerOption] = []

        // Add preset providers first
        for preset in SettingsViewModel.presetsForType(serviceType) {
            if seen.insert(preset.provider).inserted {
                options.append(.init(id: preset.provider, label: preset.provider, value: preset.provider))
            }
        }

        // Add common known providers
        let commonProviders = ["openai", "chatfire", "gemini", "openrouter", "volcengine", "minimax", "ali", "vidu"]
        for p in commonProviders {
            if seen.insert(p).inserted {
                options.append(.init(id: p, label: p, value: p))
            }
        }

        return options
    }

    private var apiKeyPlaceholder: String {
        if provider == "openai" { return "sk-..." }
        return "输入 API Key..."
    }

    // MARK: - Field Helper

    private func field(_ label: String, error: String?, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(.labelMedium)
                .foregroundStyle(Color.text1)
            content()
            if let error {
                Text(error)
                    .font(.labelSmall)
                    .foregroundStyle(Color.statusError)
            }
        }
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        field(label, error: nil, content: content)
    }

    // MARK: - Populate

    private func populateFields() {
        guard case .edit(let config) = mode else {
            // Create mode: auto-apply first preset
            let presets = SettingsViewModel.presetsForType(serviceType)
            if let first = presets.first {
                applyPreset(first)
            }
            return
        }
        name = config.name
        provider = config.provider ?? ""
        priority = config.priority
        apiKey = config.apiKey
        baseUrl = config.baseUrl
        modelText = config.model.joined(separator: ", ")
    }

    // MARK: - Template Fill

    private func applyPreset(_ preset: ProviderPreset) {
        provider = preset.provider
        baseUrl = preset.baseUrl
        modelText = preset.models.joined(separator: ", ")

        // Auto-generate name if empty or still a template name
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty || trimmedName.contains("推荐") {
            name = "\(preset.label)-\(serviceTypeLabel)"
        }

        // Clear validation errors on template apply
        clearError(&nameError)
        clearError(&apiKeyError)
        clearError(&baseUrlError)
        clearError(&modelError)
    }

    // MARK: - Validation

    private func clearError(_ error: inout String?) {
        error = nil
    }

    var isFormValid: Bool {
        validate()
        return nameError == nil && apiKeyError == nil && baseUrlError == nil && modelError == nil
    }

    @discardableResult
    private func validate() -> Bool {
        var valid = true

        // Name
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty {
            nameError = "配置名称不能为空"
            valid = false
        } else {
            nameError = nil
        }

        // API Key
        let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespaces)
        if trimmedApiKey.isEmpty {
            apiKeyError = "API Key 不能为空"
            valid = false
        } else {
            apiKeyError = nil
        }

        // Base URL — must be valid URL
        let trimmedBaseUrl = baseUrl.trimmingCharacters(in: .whitespaces)
        if trimmedBaseUrl.isEmpty {
            baseUrlError = "Base URL 不能为空"
            valid = false
        } else if !isValidURL(trimmedBaseUrl) {
            baseUrlError = "请输入有效的 URL 格式（如 https://api.openai.com）"
            valid = false
        } else {
            baseUrlError = nil
        }

        // Model
        let models = parseModels()
        if models.isEmpty {
            modelError = "模型名称不能为空"
            valid = false
        } else {
            modelError = nil
        }

        return valid
    }

    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string),
              let scheme = url.scheme,
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return false
        }
        return true
    }

    private func parseModels() -> [String] {
        modelText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Save

    func performSave() async {
        guard validate() else { return }

        isSaving = true
        saveError = nil

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedBaseUrl = baseUrl.trimmingCharacters(in: .whitespaces)
        let trimmedProvider = provider.trimmingCharacters(in: .whitespaces)
        let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespaces)
        let models = parseModels()

        do {
            switch mode {
            case .create:
                let req = CreateAIServiceConfigRequest(
                    serviceType: serviceType,
                    provider: trimmedProvider.isEmpty ? nil : trimmedProvider,
                    name: trimmedName,
                    baseUrl: trimmedBaseUrl,
                    apiKey: trimmedApiKey,
                    model: models.isEmpty ? nil : models,
                    priority: priority,
                    isActive: nil
                )
                try await APIEndpoints.AIConfigAPI.create(req)

            case .edit(let config):
                let req = UpdateAIServiceConfigRequest(
                    name: trimmedName,
                    baseUrl: trimmedBaseUrl,
                    apiKey: trimmedApiKey,
                    model: models.isEmpty ? nil : models,
                    priority: priority,
                    isActive: nil,
                    isDefault: nil
                )
                try await APIEndpoints.AIConfigAPI.update(id: config.id, req)
            }

            onSave()
        } catch {
            saveError = error.localizedDescription
        }

        isSaving = false
    }
}

// MARK: - ProviderPreset Identifiable

extension ProviderPreset: Identifiable {
    var id: String { provider }
}
