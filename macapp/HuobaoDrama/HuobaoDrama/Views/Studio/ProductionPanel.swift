import SwiftUI

// MARK: - ProductionTab

/// 制作工作台的子标签类型。
enum ProductionTab: String, CaseIterable {
    case characterImage = "角色形象"
    case sceneImage = "场景图片"
    case dubbing = "配音生成"
    case shotImage = "镜头图片"
    case videoGen = "视频生成"
    case videoCompose = "视频合成"

    /// 标签页对应的 SF Symbol 图标。
    var icon: String {
        switch self {
        case .characterImage: return "person.crop.rectangle"
        case .sceneImage: return "photo.on.rectangle.angled"
        case .dubbing: return "waveform"
        case .shotImage: return "film"
        case .videoGen: return "video.badge.plus"
        case .videoCompose: return "rectangle.stack.fill"
        }
    }
}

// MARK: - ProductionPanel

/// 制作工作台主面板（E7）。
/// 包含 6 个子标签的切换：角色形象 / 场景图片 / 配音生成 / 镜头图片 / 视频生成 / 视频合成。
struct ProductionPanel: View {
    @ObservedObject var viewModel: StudioViewModel

    /// 当前选中的子标签。
    @State private var selectedTab: ProductionTab = .characterImage

    var body: some View {
        VStack(spacing: 0) {
            tabToolbar
            Divider()
            tabContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 标签工具栏

    private var tabToolbar: some View {
        HStack(spacing: 0) {
            // 标题区域
            HStack(spacing: Spacing.sm) {
                Text("制作工作台")
                    .font(.headingMedium)
                    .foregroundStyle(Color.text0)
            }
            .padding(.trailing, Spacing.xl)

            // 子标签栏
            HStack(spacing: 2) {
                ForEach(ProductionTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(Spacing.xs)
            .background(Color.bg2)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))

            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
        .background(Color.bgCard)
    }

    /// 单个标签按钮。
    private func tabButton(_ tab: ProductionTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: tab.icon)
                    .font(.system(size: IconSize.xs, weight: .medium))
                Text(tab.rawValue)
                    .font(.labelMedium)
            }
            .foregroundStyle(isSelected ? Color.textInverse : Color.text2)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(isSelected ? Color.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 标签内容切换

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .characterImage:
            CharacterImageTab(viewModel: viewModel)
        case .sceneImage:
            SceneImageTab(viewModel: viewModel)
        case .dubbing:
            DubbingTab(viewModel: viewModel)
        case .shotImage:
            ShotImageTab(viewModel: viewModel)
        case .videoGen:
            VideoGenTab(viewModel: viewModel)
        case .videoCompose:
            VideoComposeTab(viewModel: viewModel)
        }
    }
}
