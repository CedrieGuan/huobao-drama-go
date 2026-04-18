import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            DramaListPage()
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            router.navigateToSettings()
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(Color.text2)
                        }
                        .buttonStyle(IconButtonStyle())
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .dramaDetail(let dramaId):
                        DramaDetailPage(dramaId: dramaId)
                    case .studio(let episodeId, let dramaId):
                        StudioPage(episodeId: episodeId, dramaId: dramaId)
                    case .settings:
                        SettingsPage()
                    }
                }
        }
    }
}
