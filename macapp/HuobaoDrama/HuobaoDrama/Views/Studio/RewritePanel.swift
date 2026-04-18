import SwiftUI

// MARK: - RewritePanel

/// Step 1 of the script pipeline: AI rewrite results.
/// Shows an empty state, loading indicator, or editable result depending on state.
struct RewritePanel: View {
    @ObservedObject var viewModel: StudioViewModel

    /// Local editing state, initialised from `episode.scriptContent`.
    @State private var text: String = ""

    /// Tracks whether the local text differs from what is saved.
    @State private var isDirty: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()
            contentArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadFromEpisode() }
        .onChange(of: viewModel.episode?.scriptContent) { _, newValue in
            // When the episode script content changes externally (e.g. after AI rewrite completes),
            // refresh the editor only if we are not dirty.
            if !isDirty {
                text = newValue ?? ""
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: Spacing.md) {
            Spacer()

            // Character count (shown when there is content)
            if !text.isEmpty {
                Text("\(characterCount) 字")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text3)
                    .monospacedDigit()
            }

            // Save feedback
            if viewModel.isSavingRewrite {
                ProgressView()
                    .controlSize(.small)
                Text("保存中...")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text3)
            } else if viewModel.rewriteSaveSuccess && !isDirty {
                Label("已保存", systemImage: "checkmark.circle.fill")
                    .font(.labelMedium)
                    .foregroundStyle(Color.statusSuccess)
                    .transition(.opacity)
            }

            if let error = viewModel.rewriteSaveError, isDirty {
                Text(error)
                    .font(.labelSmall)
                    .foregroundStyle(Color.statusError)
                    .lineLimit(1)
            }

            // Save button (only when there is editable content and changes)
            if hasContent {
                Button {
                    Task { await save() }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.down.to.line.compact")
                            .font(.system(size: IconSize.xs, weight: .medium))
                        Text("保存")
                            .font(.bodySmall.weight(.medium))
                    }
                    .foregroundStyle(isDirty ? Color.textInverse : Color.text3)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(isDirty ? Color.accent : Color.bg2)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSavingRewrite || !isDirty)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgCard)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isRewriting {
            loadingView
        } else if hasContent {
            editorView
        } else {
            emptyView
        }
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Visual
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.text3)
                .frame(width: 64, height: 64)
                .background(Color.bg2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

            // Title
            Text("AI 改写为格式化剧本")
                .font(.headingLarge)
                .foregroundStyle(Color.text1)

            // Description
            Text("你可以先用 AI 把原始内容整理成格式化剧本，也可以跳过这一步，直接使用原始内容继续提取角色与场景。")
                .font(.bodyMedium)
                .foregroundStyle(Color.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .lineSpacing(2)

            // Action buttons (E6.2 will wire these up)
            HStack(spacing: Spacing.md) {
                Button {
                    // TODO: E6.2 - trigger AI rewrite
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: IconSize.xs, weight: .medium))
                        Text("开始改写")
                            .font(.bodySmall.weight(.medium))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    // TODO: E6.2 - skip rewrite
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "forward.end")
                            .font(.system(size: IconSize.xs, weight: .medium))
                        Text("跳过改写")
                            .font(.bodySmall.weight(.medium))
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            // Prerequisite hint
            if !viewModel.hasRawContent {
                Text("请先在「原始内容」步骤中填写内容")
                    .font(.labelSmall)
                    .foregroundStyle(Color.text3)
                    .padding(.top, Spacing.xs)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg1)
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Spinning indicator
            ProgressView()
                .controlSize(.large)
                .tint(Color.accent)

            // Status text
            Text("正在改写剧本...")
                .font(.bodyMedium)
                .foregroundStyle(Color.text2)

            // Animated dots to reinforce in-progress state
            HStack(spacing: Spacing.xs) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.accent.opacity(0.4))
                        .frame(width: 6, height: 6)
                        .scaleEffect(pulseScale(for: index))
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

    // Pulse animation state
    @State private var pulsePhase = false

    private func pulseScale(for index: Int) -> CGFloat {
        pulsePhase ? 1.4 : 0.8
    }

    // MARK: - Editor View

    private var editorView: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder shown when text is empty (user may have cleared it)
            if text.isEmpty {
                Text("格式化剧本内容...")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.text3)
                    .padding(Spacing.lg)
                    .padding(.top, Spacing.xs)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .font(.bodyMedium)
                .foregroundStyle(Color.text0)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .onChange(of: text) { _, newValue in
                    let savedContent = viewModel.episode?.scriptContent ?? ""
                    isDirty = newValue != savedContent
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg1)
    }

    // MARK: - Helpers

    /// Whether there is any content to display (from the episode or locally edited).
    private var hasContent: Bool {
        let saved = viewModel.episode?.scriptContent
        return (saved != nil && !saved!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Character count excluding whitespace, matching the Nuxt baseline behaviour.
    private var characterCount: Int {
        text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .count
    }

    private func loadFromEpisode() {
        let saved = viewModel.episode?.scriptContent ?? ""
        text = saved
        isDirty = false
    }

    private func save() async {
        await viewModel.saveRewriteContent(text)
    }
}
