import Foundation

// MARK: - Step Status

enum StepStatus {
    case notStarted
    case inProgress
    case completed
}

// MARK: - StudioViewModel

@MainActor
final class StudioViewModel: ObservableObject {
    let episodeId: Int
    let dramaId: Int

    @Published var episode: Episode?
    @Published var drama: Drama?
    @Published var characters: [Character] = []
    @Published var scenes: [Scene] = []
    @Published var storyboards: [Storyboard] = []
    @Published var isLoading = false
    @Published var error: String?

    /// Currently active pipeline step in the sidebar.
    @Published var currentStep: StudioStep = .rawContent

    // MARK: - Rewrite State

    /// Whether an AI rewrite request is currently in-flight.
    @Published var isRewriting = false

    /// Error message from the last rewrite attempt (cleared on next attempt).
    @Published var rewriteError: String?

    init(episodeId: Int, dramaId: Int) {
        self.episodeId = episodeId
        self.dramaId = dramaId
    }

    // MARK: - Step Status

    /// Returns the status of a given pipeline step based on loaded data.
    func status(for step: StudioStep) -> StepStatus {
        switch step {
        case .rawContent:
            if let content = episode?.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .completed }
            return .notStarted
        case .rewrite:
            if episode?.scriptContent != nil { return .completed }
            if episode?.content != nil { return .inProgress }
            return .notStarted
        case .extract:
            if !characters.isEmpty { return .completed }
            if episode?.scriptContent != nil { return .inProgress }
            return .notStarted
        case .voiceAssign:
            if !characters.isEmpty && characters.allSatisfy({ $0.voiceStyle != nil }) { return .completed }
            if !characters.isEmpty { return .inProgress }
            return .notStarted
        case .storyboard:
            if !storyboards.isEmpty { return .completed }
            if !characters.isEmpty { return .inProgress }
            return .notStarted
        }
    }

    /// Number of completed steps (out of totalSteps).
    var completedStepCount: Int {
        StudioStep.allCases.filter { status(for: $0) == .completed }.count
    }

    // MARK: - Computed Helpers

    /// Display string combining drama title and episode number for the topbar.
    var topbarTitle: String {
        if let drama = drama {
            if let ep = episode {
                return "\(drama.title) · 第\(ep.episodeNumber)集"
            }
            return drama.title
        }
        return "加载中..."
    }

    /// Current step index out of total (0-based) for the progress indicator.
    var currentStepIndex: Int {
        completedStepCount
    }

    /// Total number of tracked steps for progress display.
    let totalSteps = 5

    /// Progress as a fraction 0...1
    var progressFraction: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(currentStepIndex) / Double(totalSteps)
    }

    /// Human-readable progress string, e.g. "步骤 2/5"
    var progressLabel: String {
        "步骤 \(currentStepIndex)/\(totalSteps)"
    }

    /// Description of what each completed step represents
    var stepDescriptions: [String] {
        StudioStep.allCases.compactMap { step in
            status(for: step) == .completed ? step.title : nil
        }
    }

    // MARK: - Data Loading

    func load() async {
        isLoading = true
        error = nil
        do {
            async let fetchedDrama = APIEndpoints.DramaAPI.get(id: dramaId)
            async let fetchedCharacters = APIEndpoints.EpisodeAPI.characters(episodeId: episodeId)
            async let fetchedScenes = APIEndpoints.EpisodeAPI.scenes(episodeId: episodeId)
            async let fetchedStoryboards = APIEndpoints.EpisodeAPI.storyboards(episodeId: episodeId)

            let (drama, characters, scenes, storyboards) = try await (
                fetchedDrama, fetchedCharacters, fetchedScenes, fetchedStoryboards
            )

            self.drama = drama
            self.episode = drama.episodes.first { $0.id == episodeId }
            self.characters = characters
            self.scenes = scenes
            self.storyboards = storyboards

            if self.episode == nil {
                self.error = "Episode \(episodeId) not found in drama \(dramaId)"
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func reload() async {
        await load()
    }

    // MARK: - Save Content

    @Published var isSavingContent = false
    @Published var contentSaveError: String?
    @Published var contentSaveSuccess = false

    /// Save the raw content text to the backend via `episodeAPI.update`.
    func saveContent(_ text: String) async {
        guard !isSavingContent else { return }
        isSavingContent = true
        contentSaveError = nil
        contentSaveSuccess = false

        do {
            _ = try await APIEndpoints.EpisodeAPI.update(
                id: episodeId,
                UpdateEpisodeRequest(content: text)
            )
            // Mirror locally so the step status updates immediately
            episode?.content = text
            contentSaveSuccess = true
        } catch {
            contentSaveError = error.localizedDescription
        }

        isSavingContent = false
    }

    // MARK: - Save Rewrite Content

    @Published var isSavingRewrite = false
    @Published var rewriteSaveError: String?
    @Published var rewriteSaveSuccess = false

    /// Whether the raw content step has any content entered.
    var hasRawContent: Bool {
        if let content = episode?.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    /// Save the rewrite result (script_content) to the backend.
    func saveRewriteContent(_ text: String) async {
        guard !isSavingRewrite else { return }
        isSavingRewrite = true
        rewriteSaveError = nil
        rewriteSaveSuccess = false

        do {
            _ = try await APIEndpoints.EpisodeAPI.update(
                id: episodeId,
                UpdateEpisodeRequest(scriptContent: text)
            )
            episode?.scriptContent = text
            rewriteSaveSuccess = true
        } catch {
            rewriteSaveError = error.localizedDescription
        }

        isSavingRewrite = false
    }
}
