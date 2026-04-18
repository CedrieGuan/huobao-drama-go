import Foundation

@MainActor
final class DramaDetailViewModel: ObservableObject {
    let dramaId: Int

    @Published var drama: Drama?
    @Published var isLoading = false
    @Published var isCreating = false
    @Published var error: String?

    @Published var imageConfigs: [AIServiceConfig] = []
    @Published var videoConfigs: [AIServiceConfig] = []
    @Published var audioConfigs: [AIServiceConfig] = []

    init(dramaId: Int) {
        self.dramaId = dramaId
    }

    // MARK: - Data Loading

    func load() async {
        isLoading = true
        error = nil
        do {
            drama = try await APIEndpoints.DramaAPI.get(id: dramaId)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
        await loadConfigs()
    }

    func reload() async {
        await load()
    }

    // MARK: - Config Loading

    func loadConfigs() async {
        do {
            let all: [AIServiceConfig] = try await APIEndpoints.AIConfigAPI.list()
            imageConfigs = all.filter { $0.serviceType == "image" }
            videoConfigs = all.filter { $0.serviceType == "video" }
            audioConfigs = all.filter { $0.serviceType == "audio" }
        } catch {
            // Config loading failure is non-fatal; configs will remain empty
        }
    }

    // MARK: - Episode Actions

    /// Creates a new episode. Returns `true` on success, `false` on failure.
    /// On success the episode list is automatically refreshed.
    /// On failure `self.error` is populated for the View to display.
    @discardableResult
    func addEpisode(
        title: String? = nil,
        imageConfigId: Int,
        videoConfigId: Int,
        audioConfigId: Int
    ) async -> Bool {
        error = nil
        isCreating = true
        do {
            let req = CreateEpisodeRequest(
                dramaId: dramaId,
                title: title,
                imageConfigId: imageConfigId,
                videoConfigId: videoConfigId,
                audioConfigId: audioConfigId
            )
            _ = try await APIEndpoints.EpisodeAPI.create(req)
            await load()
            isCreating = false
            return true
        } catch {
            self.error = error.localizedDescription
            isCreating = false
            return false
        }
    }

    /// Returns the Route needed to navigate to the studio for a given episode.
    /// The View layer is responsible for calling Router.navigate(to:) with this route.
    func enterStudio(episodeId: Int) -> Route {
        .studio(episodeId: episodeId, dramaId: dramaId)
    }
}
