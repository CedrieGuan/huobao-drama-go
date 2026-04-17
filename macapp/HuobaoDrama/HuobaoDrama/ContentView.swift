import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            PlaceholderListView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .dramaDetail(let dramaId):
                        Text("Drama Detail \(dramaId)")
                    case .studio(let episodeId, let dramaId):
                        Text("Studio ep=\(episodeId) drama=\(dramaId)")
                    }
                }
        }
    }
}

struct PlaceholderListView: View {
    var body: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "film.stack")
                .imageScale(.large)
                .font(.system(size: 60))
                .foregroundStyle(Color.accent)

            Text("火爆短剧")
                .font(.displayMedium)
                .foregroundStyle(Color.text0)

            Text("AI 驱动的短剧制作工具")
                .font(.bodyLarge)
                .foregroundStyle(Color.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg1)
    }
}
