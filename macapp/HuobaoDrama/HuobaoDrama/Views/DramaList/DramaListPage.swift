import SwiftUI

struct DramaListPage: View {
    @State private var viewModel = DramaListViewModel()
    @Environment(Router.self) private var router

    @State private var showCreateDialog = false
    @State private var formTitle = ""
    @State private var formEpisodes = 1
    @State private var formStyle = ""
    @State private var dramaToDelete: Drama?

    private let styles = ["realistic", "anime", "ghibli", "cinematic", "comic", "watercolor"]

    var body: some View {
        VStack(spacing: 0) {
            header
            errorBanner
            content
        }
        .background(Color.bg1)
        .task { await viewModel.load() }
        .onAppear { Task { if !viewModel.items.isEmpty { await viewModel.reload() } } }
        .appSheet(
            isPresented: $showCreateDialog,
            title: "新建短剧项目",
            subtitle: "输入项目基本信息，即可开始制作",
            onConfirm: { Task { await submitCreate() } },
            confirmTitle: "创建项目",
            confirmDisabled: formTitle.trimmingCharacters(in: .whitespaces).isEmpty,
            isLoading: viewModel.isCreating
        ) {
            createForm
        }
        .alert("删除项目", isPresented: Binding(
            get: { dramaToDelete != nil },
            set: { if !$0 { dramaToDelete = nil } }
        )) {
            Button("取消", role: .cancel) { dramaToDelete = nil }
            Button("删除", role: .destructive) {
                if let d = dramaToDelete {
                    Task { await viewModel.delete(d) }
                    dramaToDelete = nil
                }
            }
        } message: {
            if let d = dramaToDelete {
                Text("确定删除「\(d.title)」？此操作不可恢复。")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("短剧项目")
                    .font(.displayMedium)
                    .foregroundStyle(Color.text0)
                Text("\(viewModel.items.count) 个项目")
                    .font(.bodySmall)
                    .foregroundStyle(Color.text3)
            }
            Spacer()
            HStack(spacing: Spacing.sm) {
                Button {
                    Task { await viewModel.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: IconSize.sm))
                        .foregroundStyle(Color.text2)
                }
                .buttonStyle(IconButtonStyle())
                .disabled(viewModel.isLoading)

                Button {
                    formTitle = ""
                    formEpisodes = 1
                    formStyle = ""
                    showCreateDialog = true
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus")
                            .font(.system(size: IconSize.xs, weight: .semibold))
                        Text("新建项目")
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

    // MARK: - Error Banner

    private var errorBanner: some View {
        Group {
            if let error = viewModel.error {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.statusError)
                    Text(error)
                        .font(.bodySmall)
                        .foregroundStyle(Color.text1)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        viewModel.clearError()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: IconSize.xs))
                            .foregroundStyle(Color.text3)
                    }
                    .buttonStyle(IconButtonStyle())
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(Color.statusError.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .padding(.horizontal, Spacing.xxxl)
                .padding(.bottom, Spacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Animation.fast, value: viewModel.error)
    }

    // MARK: - Content

    private var content: some View {
        Group {
            if viewModel.isLoading {
                loadingGrid
            } else if viewModel.items.isEmpty {
                emptyState
            } else {
                dramaGrid
            }
        }
        .padding(.horizontal, Spacing.xxxl)
    }

    private var dramaGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: Spacing.xl)],
                spacing: Spacing.xl
            ) {
                ForEach(viewModel.items) { drama in
                    ProjectCardView(drama: drama) {
                        dramaToDelete = drama
                    } onTap: {
                        router.navigate(to: .dramaDetail(dramaId: drama.id))
                    }
                }
            }
            .padding(.vertical, Spacing.lg)
        }
    }

    private var loadingGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: Spacing.xl)],
                spacing: Spacing.xl
            ) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: 0) {
                        // Film strip
                        HStack(spacing: 0) {
                            ForEach(0..<5, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.bg3.opacity(0.5))
                                    .frame(width: 10, height: 8)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .padding(.horizontal, Spacing.lg)
                        .background(Color.bg2)
                        // Body placeholder
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            RoundedRectangle(cornerRadius: Radius.sm).fill(Color.bg3).frame(width: 48, height: 12)
                            RoundedRectangle(cornerRadius: Radius.sm).fill(Color.bg3).frame(height: 14)
                            HStack(spacing: Spacing.sm) {
                                RoundedRectangle(cornerRadius: 99).fill(Color.bg3).frame(width: 52, height: 16)
                                RoundedRectangle(cornerRadius: Radius.sm).fill(Color.bg3).frame(width: 20, height: 12)
                            }
                        }
                        .padding(Spacing.lg)
                        // Footer
                        HStack(spacing: Spacing.sm) {
                            RoundedRectangle(cornerRadius: 99).fill(Color.bg3).frame(height: 3)
                            RoundedRectangle(cornerRadius: Radius.sm).fill(Color.bg3).frame(width: 48, height: 10)
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                    }
                    .background(Color.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                    .shimmer(isActive: true)
                }
            }
            .padding(.vertical, Spacing.lg)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "plus.rectangle",
            title: "新建第一个短剧项目",
            message: "从剧本到成片，AI 助力的短剧制作工作台",
            actionTitle: "新建项目",
            action: { showCreateDialog = true }
        )
    }

    // MARK: - Create Form

    private var createForm: some View {
        VStack(spacing: Spacing.lg) {
            field("项目名称 *") {
                TextField("例如：都市情感短剧《时光邮局》", text: $formTitle)
                    .textFieldStyle(AppTextFieldStyle())
            }
            HStack(spacing: Spacing.md) {
                field("计划集数") {
                    Stepper(value: $formEpisodes, in: 1...100) {
                        TextField("", value: $formEpisodes, format: .number)
                            .textFieldStyle(AppTextFieldStyle())
                            .frame(width: 60)
                    }
                }
                field("视觉风格") {
                    Picker("", selection: $formStyle) {
                        Text("选择风格").tag("")
                        ForEach(styles, id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }
                    .labelsHidden()
                }
            }
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

    private func submitCreate() async {
        guard let drama = await viewModel.create(title: formTitle, totalEpisodes: formEpisodes, style: formStyle.isEmpty ? nil : formStyle) else { return }
        showCreateDialog = false
        router.navigate(to: .dramaDetail(dramaId: drama.id))
    }
}
