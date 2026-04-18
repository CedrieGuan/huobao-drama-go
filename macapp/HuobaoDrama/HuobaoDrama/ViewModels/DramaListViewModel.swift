import Foundation

@MainActor
final class DramaListViewModel: ObservableObject {
    @Published var items: [Drama] = []
    @Published var isLoading = false
    @Published var error: String?

    func load() async {
        isLoading = true
        error = nil
        do {
            let page: PaginatedResponse<Drama> = try await APIEndpoints.DramaAPI.list()
            items = page.items
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func reload() async {
        await load()
    }
}
