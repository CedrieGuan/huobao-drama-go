import SwiftUI

// MARK: - InlineAsyncImage

/// 轻量级内联异步图片组件。
/// 用于在列表和卡片中直接展示远程图片，不提供全屏查看功能。
struct InlineAsyncImage: View {
    var urlString: String
    var aspectRatio: CGFloat = 16 / 9

    private var fullURL: String {
        if urlString.hasPrefix("http") { return urlString }
        return ConnectionSettingsStore.shared.baseURL + urlString
    }

    var body: some View {
        AsyncImage(url: URL(string: fullURL)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(aspectRatio, contentMode: .fit)
            case .failure:
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.text3)
            default:
                ProgressView()
                    .tint(Color.accent)
            }
        }
    }
}
