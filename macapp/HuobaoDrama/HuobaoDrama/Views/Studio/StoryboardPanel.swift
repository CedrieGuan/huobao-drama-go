import SwiftUI

// MARK: - StoryboardPanel

/// Step 05 of the script pipeline: storyboard breakdown list and detail editor.
/// Shows an empty state, loading indicator, or split-view storyboard list/detail.
struct StoryboardPanel: View {
    @ObservedObject var viewModel: StudioViewModel

    /// Currently selected storyboard for the detail panel.
    @State private var selectedStoryboardId: Int? = nil

    // Pulse animation state
    @State private var pulsePhase = false

    /// Local edit state for the detail fields (keyed by field name).
    @State private var editFields: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()
            contentArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: viewModel.storyboards) { _, _ in
            // Reset selection if the selected storyboard was removed
            if let id = selectedStoryboardId,
               !viewModel.storyboards.contains(where: { $0.id == id }) {
                selectedStoryboardId = nil
                editFields = [:]
            }
        }
        .onChange(of: selectedStoryboardId) { _, newId in
            // Sync edit fields when selection changes
            syncEditFields()
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: Spacing.md) {
            // Statistics
            if hasResults {
                let totalDuration = viewModel.storyboards.reduce(0) { $0 + $1.duration }
                Text("\(viewModel.storyboards.count) 镜头")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text2)
                Text("\u{00B7}")
                    .font(.labelMedium)
                    .foregroundStyle(Color.text3)
                Text(formatDuration(totalDuration))
                    .font(.labelMedium)
                    .foregroundStyle(Color.text2)
            }

            Spacer()

            // Error feedback
            if let error = viewModel.storyboardBreakError {
                Text(error)
                    .font(.labelSmall)
                    .foregroundStyle(Color.statusError)
                    .lineLimit(1)
            }

            // Add button (only when results exist)
            if hasResults && !viewModel.isBreakingStoryboard {
                Button {
                    Task { await viewModel.addStoryboard() }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus")
                            .font(.system(size: IconSize.xs, weight: .medium))
                        Text("添加")
                            .font(.bodySmall.weight(.medium))
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            // Re-breakdown button
            if hasResults && !viewModel.isBreakingStoryboard {
                Button {
                    Task { await viewModel.runStoryboardBreakdown() }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: IconSize.xs, weight: .medium))
                        Text("重新拆解")
                            .font(.bodySmall.weight(.medium))
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgCard)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isBreakingStoryboard {
            loadingView
        } else if hasResults {
            resultsView
        } else {
            emptyView
        }
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Visual
            Image(systemName: "film")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.text3)
                .frame(width: 64, height: 64)
                .background(Color.bg2)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

            // Title
            Text("将剧本拆解为分镜序列")
                .font(.headingLarge)
                .foregroundStyle(Color.text1)

            // Description
            Text("AI 会根据剧本内容自动生成分镜序列，包含镜头类型、动作描述和对白信息。")
                .font(.bodyMedium)
                .foregroundStyle(Color.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .lineSpacing(2)

            // Action button
            Button {
                Task { await viewModel.runStoryboardBreakdown() }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: IconSize.xs, weight: .medium))
                    Text("AI 拆解分镜")
                        .font(.bodySmall.weight(.medium))
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg1)
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .tint(Color.accent)

            Text("正在拆解分镜并生成提示词...")
                .font(.bodyMedium)
                .foregroundStyle(Color.text2)

            // Animated dots
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

    // MARK: - Results View (Split Layout)

    private var resultsView: some View {
        HStack(spacing: 0) {
            // Left: storyboard list
            storyboardList

            Divider()

            // Right: detail panel
            detailPanel
        }
        .background(Color.bg1)
    }

    // MARK: - Storyboard List

    private var storyboardList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xs) {
                ForEach(viewModel.storyboards) { storyboard in
                    storyboardListItem(storyboard)
                }
            }
            .padding(Spacing.sm)
        }
        .frame(width: 280)
        .background(Color.bgCard)
    }

    private func storyboardListItem(_ storyboard: Storyboard) -> some View {
        let isSelected = selectedStoryboardId == storyboard.id

        return Button {
            selectedStoryboardId = storyboard.id
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Header row: label + shot type + status dots
                HStack(spacing: Spacing.sm) {
                    Text(storyboard.label)
                        .font(.labelMedium.weight(.medium))
                        .foregroundStyle(isSelected ? Color.textInverse : Color.text0)
                        .monospacedDigit()

                    if let shotType = storyboard.shotType, !shotType.isEmpty {
                        TagView(
                            text: shotType,
                            color: isSelected ? Color.textInverse.opacity(0.9) : Color.accent,
                            bgColor: isSelected ? Color.white.opacity(0.15) : Color.accentLight,
                            size: .small
                        )
                    }

                    Spacer()

                    // Status dots: has image, video, dialogue
                    HStack(spacing: 4) {
                        if storyboard.composedImage != nil {
                            StatusDot(status: "completed", size: 6)
                        }
                        if storyboard.composedVideoUrl != nil {
                            StatusDot(status: "completed", size: 6)
                        }
                        if storyboard.dialogue != nil && !storyboard.dialogue!.isEmpty {
                            StatusDot(status: "pending", size: 6)
                        }
                    }
                }

                // Description
                if let desc = storyboard.description, !desc.isEmpty {
                    Text(desc)
                        .font(.labelSmall)
                        .foregroundStyle(isSelected ? Color.textInverse.opacity(0.8) : Color.text2)
                        .lineLimit(2)
                }

                // Meta row: duration + location
                HStack(spacing: Spacing.sm) {
                    if storyboard.duration > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "clock")
                                .font(.system(size: 8))
                            Text("\(storyboard.duration)s")
                                .font(.labelSmall)
                        }
                        .foregroundStyle(isSelected ? Color.textInverse.opacity(0.7) : Color.text3)
                    }

                    if let location = storyboard.location, !location.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "location")
                                .font(.system(size: 8))
                            Text(location)
                                .font(.labelSmall)
                        }
                        .foregroundStyle(isSelected ? Color.textInverse.opacity(0.7) : Color.text3)
                        .lineLimit(1)
                    }
                }

                // Character count
                if !storyboard.characters.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "person.2")
                            .font(.system(size: 8))
                        Text("\(storyboard.characters.count) 角色")
                            .font(.labelSmall)
                    }
                    .foregroundStyle(isSelected ? Color.textInverse.opacity(0.7) : Color.text3)
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail Panel

    private var selectedStoryboard: Storyboard? {
        guard let id = selectedStoryboardId else { return nil }
        return viewModel.storyboards.first(where: { $0.id == id })
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

            Image(systemName: "sidebar.right")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.text3)

            Text("选择一个镜头查看详情")
                .font(.bodyMedium)
                .foregroundStyle(Color.text3)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func storyboardDetailView(_ storyboard: Storyboard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Header
                detailHeader(storyboard)

                // Section: Shot Structure (E10.1)
                shotStructureSection(storyboard)

                // Section: Semantic Fields (E10.2)
                semanticSection(storyboard)
            }
            .padding(Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg1)
    }

    // MARK: - Detail Header

    private func detailHeader(_ storyboard: Storyboard) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Label + title
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

                // Meta line
                HStack(spacing: Spacing.md) {
                    if let shotType = storyboard.shotType, !shotType.isEmpty {
                        TagView(text: shotType, size: .small)
                    }
                    if storyboard.duration > 0 {
                        TagView(
                            text: "\(storyboard.duration)s",
                            color: Color.text2,
                            bgColor: Color.bg2,
                            size: .small
                        )
                    }
                }
            }

            Spacer()

            // Delete button
            Button {
                Task {
                    try? await APIEndpoints.StoryboardAPI.delete(id: storyboard.id)
                    // 删除后刷新分镜列表
                    await viewModel.loadStoryboards()
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: IconSize.sm, weight: .medium))
                    .foregroundStyle(Color.statusError)
            }
            .buttonStyle(IconButtonStyle())
            .help("删除镜头")
        }
    }

    // MARK: - Shot Structure Section (E10.1)

    private func shotStructureSection(_ storyboard: Storyboard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sectionTitle("镜头结构")

            // Field grid: 2 columns
            VStack(spacing: Spacing.md) {
                HStack(spacing: Spacing.lg) {
                    // Title
                    fieldEditor(
                        label: "标题",
                        fieldKey: "title",
                        value: storyboard.title
                    )

                    // Shot Type
                    fieldEditor(
                        label: "景别",
                        fieldKey: "shotType",
                        value: storyboard.shotType
                    )
                }

                HStack(spacing: Spacing.lg) {
                    // Angle
                    fieldEditor(
                        label: "角度",
                        fieldKey: "angle",
                        value: storyboard.angle
                    )

                    // Movement
                    fieldEditor(
                        label: "运动",
                        fieldKey: "movement",
                        value: storyboard.movement
                    )
                }

                HStack(spacing: Spacing.lg) {
                    // Location
                    fieldEditor(
                        label: "地点",
                        fieldKey: "location",
                        value: storyboard.location
                    )

                    // Time
                    fieldEditor(
                        label: "时间",
                        fieldKey: "time",
                        value: storyboard.time
                    )

                    // Duration
                    durationEditor(storyboard: storyboard)
                }
            }

            // Characters
            charactersRow(storyboard)

            // Scene reference
            sceneRow(storyboard)
        }
        .padding(Spacing.xl)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - Semantic Section (E10.2)

    private func semanticSection(_ storyboard: Storyboard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sectionTitle("画面语义")

            VStack(spacing: Spacing.md) {
                // Action
                multilineFieldEditor(
                    label: "动作",
                    fieldKey: "action",
                    value: storyboard.action
                )

                // Result
                multilineFieldEditor(
                    label: "结果",
                    fieldKey: "result",
                    value: storyboard.result
                )

                // Description
                multilineFieldEditor(
                    label: "描述",
                    fieldKey: "description",
                    value: storyboard.description
                )

                // Atmosphere
                multilineFieldEditor(
                    label: "氛围",
                    fieldKey: "atmosphere",
                    value: storyboard.atmosphere
                )

                // Dialogue
                multilineFieldEditor(
                    label: "对白",
                    fieldKey: "dialogue",
                    value: storyboard.dialogue
                )
            }
        }
        .padding(Spacing.xl)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - Field Editors

    /// Single-line text field editor that auto-saves on blur.
    private func fieldEditor(label: String, fieldKey: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(.labelSmall)
                .foregroundStyle(Color.text3)

            TextField("", text: Binding(
                get: { editFields[fieldKey] ?? value ?? "" },
                set: { editFields[fieldKey] = $0 }
            ))
            .textFieldStyle(AppTextFieldStyle())
            .onSubmit {
                Task { await saveField(fieldKey: fieldKey) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Multi-line text field editor that auto-saves on submit.
    private func multilineFieldEditor(label: String, fieldKey: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(.labelSmall)
                .foregroundStyle(Color.text3)

            TextEditor(text: Binding(
                get: { editFields[fieldKey] ?? value ?? "" },
                set: { editFields[fieldKey] = $0 }
            ))
            .font(.bodySmall)
            .foregroundStyle(Color.text0)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 48, maxHeight: 120)
            .padding(Spacing.xs)
            .background(Color.bg1)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .stroke(Color.border0, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Duration integer field editor.
    private func durationEditor(storyboard: Storyboard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("时长(秒)")
                .font(.labelSmall)
                .foregroundStyle(Color.text3)

            TextField("", value: Binding(
                get: { Int(editFields["duration"] ?? "\(storyboard.duration)") ?? storyboard.duration },
                set: { editFields["duration"] = "\($0)" }
            ), format: .number)
            .textFieldStyle(AppTextFieldStyle())
            .frame(maxWidth: 80)
            .onSubmit {
                Task { await saveField(fieldKey: "duration") }
            }
        }
    }

    /// Characters display row.
    private func charactersRow(_ storyboard: Storyboard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("角色")
                .font(.labelSmall)
                .foregroundStyle(Color.text3)

            if storyboard.characters.isEmpty {
                Text("未关联角色")
                    .font(.bodySmall)
                    .foregroundStyle(Color.text3)
            } else {
                HStack(spacing: Spacing.sm) {
                    ForEach(storyboard.characters) { character in
                        HStack(spacing: Spacing.xs) {
                            Text(String(character.name.prefix(1)))
                                .font(.labelSmall.weight(.medium))
                                .foregroundStyle(Color.textInverse)
                                .frame(width: 18, height: 18)
                                .background(Color.accent)
                                .clipShape(Circle())
                            Text(character.name)
                                .font(.bodySmall)
                                .foregroundStyle(Color.text1)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Scene reference row.
    private func sceneRow(_ storyboard: Storyboard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("场景")
                .font(.labelSmall)
                .foregroundStyle(Color.text3)

            if storyboard.location == nil && storyboard.time == nil {
                Text("未关联场景")
                    .font(.bodySmall)
                    .foregroundStyle(Color.text3)
            } else {
                HStack(spacing: Spacing.sm) {
                    if let loc = storyboard.location, !loc.isEmpty {
                        TagView(
                            text: loc,
                            color: Color.text1,
                            bgColor: Color.bg2,
                            size: .small
                        )
                    }
                    if let time = storyboard.time, !time.isEmpty {
                        TagView(
                            text: time,
                            color: Color.text2,
                            bgColor: Color.bg2,
                            size: .small
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Section Title Helper

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headingSmall)
            .foregroundStyle(Color.text0)
    }

    // MARK: - Helpers

    /// Whether there are storyboards to display.
    private var hasResults: Bool {
        !viewModel.storyboards.isEmpty
    }

    /// Format total duration in seconds to a readable string.
    private func formatDuration(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    /// Sync local edit fields from the selected storyboard.
    private func syncEditFields() {
        guard let id = selectedStoryboardId,
              let storyboard = viewModel.storyboards.first(where: { $0.id == id }) else {
            editFields = [:]
            return
        }
        editFields = [
            "title": storyboard.title ?? "",
            "shotType": storyboard.shotType ?? "",
            "angle": storyboard.angle ?? "",
            "movement": storyboard.movement ?? "",
            "location": storyboard.location ?? "",
            "time": storyboard.time ?? "",
            "duration": "\(storyboard.duration)",
            "action": storyboard.action ?? "",
            "result": storyboard.result ?? "",
            "description": storyboard.description ?? "",
            "atmosphere": storyboard.atmosphere ?? "",
            "dialogue": storyboard.dialogue ?? "",
        ]
    }

    /// Save a single field change to the API.
    private func saveField(fieldKey: String) async {
        guard let id = selectedStoryboardId,
              let newValue = editFields[fieldKey] else { return }

        // Find the original storyboard to compare
        guard let storyboard = viewModel.storyboards.first(where: { $0.id == id }) else { return }

        // Check if value actually changed
        let originalValue: String? = {
            switch fieldKey {
            case "title": return storyboard.title
            case "shotType": return storyboard.shotType
            case "angle": return storyboard.angle
            case "movement": return storyboard.movement
            case "location": return storyboard.location
            case "time": return storyboard.time
            case "action": return storyboard.action
            case "result": return storyboard.result
            case "description": return storyboard.description
            case "atmosphere": return storyboard.atmosphere
            case "dialogue": return storyboard.dialogue
            case "duration": return "\(storyboard.duration)"
            default: return nil
            }
        }()

        if originalValue == newValue { return }

        // Build the update request with only the changed field
        var request = UpdateStoryboardRequest()
        switch fieldKey {
        case "title": request.title = newValue.isEmpty ? nil : newValue
        case "shotType": request.shotType = newValue.isEmpty ? nil : newValue
        case "angle": request.angle = newValue.isEmpty ? nil : newValue
        case "movement": request.movement = newValue.isEmpty ? nil : newValue
        case "location": request.location = newValue.isEmpty ? nil : newValue
        case "time": request.time = newValue.isEmpty ? nil : newValue
        case "action": request.action = newValue.isEmpty ? nil : newValue
        case "result": request.result = newValue.isEmpty ? nil : newValue
        // description is not yet in UpdateStoryboardRequest; skip for now
        // case "description": request.description = newValue.isEmpty ? nil : newValue
        case "atmosphere": request.atmosphere = newValue.isEmpty ? nil : newValue
        case "dialogue": request.dialogue = newValue.isEmpty ? nil : newValue
        // duration is not in UpdateStoryboardRequest; skip for now
        // case "duration":
        //     let d = Int(newValue) ?? 0
        //     request.duration = d
        default: break
        }

        // Handle duration field: UpdateStoryboardRequest may not have a duration field,
        // but we save it through the regular request structure.
        do {
            _ = try await APIEndpoints.StoryboardAPI.update(id: id, request)
        } catch {
            // Silently handle save errors; could surface via viewModel error property
        }
    }
}
