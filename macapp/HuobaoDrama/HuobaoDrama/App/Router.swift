import SwiftUI

enum Route: Hashable {
    case dramaDetail(dramaId: Int)
    case studio(episodeId: Int, dramaId: Int)
    case settings
}

@MainActor
@Observable
final class Router {
    var path: [Route] = []

    func navigate(to route: Route) {
        path.append(route)
    }

    func pop() {
        if !path.isEmpty { path.removeLast() }
    }

    func popToRoot() {
        path.removeAll()
    }

    func navigateToSettings() {
        path.append(.settings)
    }
}
