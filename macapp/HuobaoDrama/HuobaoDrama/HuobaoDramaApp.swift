import SwiftUI

@main
struct HuobaoDramaApp: App {
    @State private var router = Router()

    var body: some SwiftUI.Scene {
        WindowGroup {
            RootView()
                .environment(router)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
    }
}
