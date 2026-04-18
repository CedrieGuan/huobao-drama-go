import SwiftUI

// MARK: - RawContentPanel

/// Step 0 of the script pipeline: paste / edit raw content,
/// live character count, and manual save.
struct RawContentPanel: View {
    @ObservedObject var viewModel: StudioViewModel

    /// Local editing state, initialised from `episode.content`.
    @State private var text: String = ""

    /// Tracks whether the local text differs from what is saved.
    @State private var isDirty: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()
            editorArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadFromEpisode() }
        .onChange(of: viewModel.episode?.content) { _, newValue in
            // When the episode content changes externally (e.g. reload),
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

            // Character count
            Text("\(characterCount) 字")
                .font(.labelMedium)
                .foregroundStyle(Color.text3)
                .monospacedDigit()

            // Save feedback
            if viewModel.isSavingContent {
                ProgressView()
                    .controlSize(.small)
                Text("保存中...")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text3)
            } else if viewModel.contentSaveSuccess && !isDirty {
                Label("已保存", systemImage: "checkmark.circle.fill")
                    .font(.labelMedium)
                    .foregroundStyle(Color.statusSuccess)
                    .transition(.opacity)
            }

            if let error = viewModel.contentSaveError, isDirty {
                Text(error)
                    .font(.labelSmall)
                    .foregroundStyle(Color.statusError)
                    .lineLimit(1)
            }

            // Save button
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
            .disabled(viewModel.isSavingContent || !isDirty)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgCard)
    }

    // MARK: - Editor Area

    private var editorArea: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder shown when text is empty
            if text.isEmpty {
                Text("在此粘贴或输入原始剧本内容...")
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
                    let savedContent = viewModel.episode?.content ?? ""
                    isDirty = newValue != savedContent
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg1)
    }

    // MARK: - Helpers

    /// Character count excluding whitespace, matching the Nuxt baseline behaviour.
    private var characterCount: Int {
        text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .count
    }

    private func loadFromEpisode() {
        let saved = viewModel.episode?.content ?? ""
        text = saved
        isDirty = false
    }

    private func save() async {
        await viewModel.saveContent(text)
    }
}
