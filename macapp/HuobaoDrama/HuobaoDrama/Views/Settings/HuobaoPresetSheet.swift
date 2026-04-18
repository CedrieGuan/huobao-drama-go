import SwiftUI

/// D5.1 + D5.2: 火宝一键预设弹窗 -- API Key 输入 + 预设确认 + 批量创建。
///
/// 参考 Nuxt settings.vue 中 presetDialog + applyHuobaoPreset 的逻辑。
struct HuobaoPresetSheet: View {

    let viewModel: SettingsViewModel
    let onConfirm: () -> Void
    let onCancel: () -> Void

    // MARK: - State

    @State private var apiKey: String = ""
    @State private var apiKeyError: String?
    @State private var isSubmitting = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // API Key field
                    apiKeyField

                    // Preset preview cards
                    presetPreviewSection
                }
                .padding(Spacing.lg)
            }

            Divider()

            // Footer actions
            actionBar
        }
        .frame(maxWidth: 520)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .modalShadow()
        .onKeyPress(.escape) { if !isSubmitting { onCancel(); return .handled }; return .ignored }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("HUOBAO PRESET")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.text3)
                Text("火宝一键配置")
                    .font(.headingMedium)
                    .foregroundStyle(Color.text0)
                Text("按火宝推荐链路自动创建 4 条服务配置（文本 / 图片 / 视频 / 音频）。")
                    .font(.bodySmall)
                    .foregroundStyle(Color.text2)
            }
            Spacer()
            TagView(text: "推荐", color: Color.statusSuccess, bgColor: Color.statusSuccessLight, size: .small)
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.text2)
                    .padding(Spacing.xs)
                    .background(Color.bg2)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
        }
        .padding(Spacing.lg)
    }

    // MARK: - API Key Field

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Text("Huobao API Key")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text1)
                Text("(统一用于文本 / 图片 / 视频 / 音频)")
                    .font(.labelSmall)
                    .foregroundStyle(Color.text3)
            }
            SecureField("用于 api.chatfire.site 全链路服务", text: $apiKey)
                .textFieldStyle(AppTextFieldStyle())
                .disabled(isSubmitting)
                .onChange(of: apiKey) { _, _ in apiKeyError = nil }

            if let apiKeyError {
                Text(apiKeyError)
                    .font(.labelSmall)
                    .foregroundStyle(Color.statusError)
            }

            HStack(spacing: Spacing.xs) {
                Text("还没有账号？")
                    .font(.labelSmall)
                    .foregroundStyle(Color.text3)
                Link("立即注册", destination: URL(string: "https://api.chatfire.site/")!)
                    .font(.labelSmall)
                    .foregroundStyle(Color.accent)
            }
        }
    }

    // MARK: - Preset Preview

    private var presetPreviewSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("将创建以下配置")
                .font(.labelMedium)
                .foregroundStyle(Color.text2)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                ForEach(SettingsViewModel.huobaoPresetCards, id: \.serviceType) { card in
                    presetPreviewCard(card)
                }
            }
        }
    }

    private func presetPreviewCard(_ card: PresetCard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(card.label)
                    .font(.labelMedium)
                    .foregroundStyle(Color.text0)
                Spacer()
                TagView(text: card.provider, color: Color.accent, bgColor: Color.accentLight, size: .small)
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
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Color.bg1))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Color.border0, lineWidth: 1))
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: Spacing.sm) {
            Spacer()
            Button("取消") {
                onCancel()
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(isSubmitting)

            Button {
                performConfirm()
            } label: {
                HStack(spacing: Spacing.xs) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isSubmitting ? "创建中…" : "创建并启用")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isSubmitting)
        }
        .padding(Spacing.lg)
    }

    // MARK: - Actions

    private func performConfirm() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            apiKeyError = "请填写 Huobao API Key"
            return
        }

        isSubmitting = true
        Task {
            let success = await viewModel.createHuobaoPresets(apiKey: trimmed)
            isSubmitting = false
            if success {
                onConfirm()
            }
            // On failure the toast is already set by the ViewModel;
            // the sheet stays open so the user can retry.
        }
    }
}
