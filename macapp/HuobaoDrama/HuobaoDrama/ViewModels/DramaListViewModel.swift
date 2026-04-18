import Foundation

@MainActor
final class DramaListViewModel: ObservableObject {
    @Published var items: [Drama] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var isCreating = false

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

    @discardableResult
    func create(title: String, totalEpisodes: Int = 1, style: String? = nil) async -> Drama? {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        isCreating = true
        do {
            let req = CreateDramaRequest(
                title: title,
                description: nil,
                genre: nil,
                style: style,
                totalEpisodes: totalEpisodes,
                tags: nil
            )
            let drama = try await APIEndpoints.DramaAPI.create(req)
            items.insert(drama, at: 0)
            isCreating = false
            return drama
        } catch {
            self.error = error.localizedDescription
            isCreating = false
            return nil
        }
    }

    func delete(_ drama: Drama) async {
        do {
            try await APIEndpoints.DramaAPI.delete(id: drama.id)
            items.removeAll { $0.id == drama.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func clearError() {
        error = nil
    }
}
