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

    // MARK: - Extract State

    /// Whether a character/scene extraction request is currently in-flight.
    @Published var isExtracting = false

    /// Error message from the last extract attempt.
    @Published var extractError: String?

    // MARK: - Voice Assignment State

    /// Whether a voice assignment request is currently in-flight.
    @Published var isAssigningVoices = false

    /// Error message from the last voice assignment attempt.
    @Published var voiceAssignError: String?

    // MARK: - Storyboard Breakdown State

    /// Whether a storyboard breakdown request is currently in-flight.
    @Published var isBreakingStoryboard = false

    /// Error message from the last storyboard breakdown attempt.
    @Published var storyboardBreakError: String?

    // MARK: - Voice Profiles State

    /// Available voice profiles loaded from the backend.
    @Published var voiceProfiles: [VoiceProfile] = []

    /// Whether voice profiles are currently being loaded.
    @Published var isLoadingVoices = false

    // MARK: - Agent Running State (E1.2)

    /// The current running agent type (for loading indicator targeting).
    @Published var runningAgentType: String?

    /// Whether any agent is currently running.
    var isAgentRunning: Bool { runningAgentType != nil }

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

    /// Whether the main CTA for the current step should be shown.
    func canRunCurrentStep() -> Bool {
        guard !isAgentRunning else { return false }
        switch currentStep {
        case .rawContent: return true
        case .rewrite: return hasRawContent
        case .extract: return episode?.scriptContent != nil
        case .voiceAssign: return !characters.isEmpty
        case .storyboard: return !characters.isEmpty
        }
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

    // MARK: - AI Rewrite (E6.2)

    /// Trigger AI rewrite via script_rewriter agent.
    func runRewrite() async {
        guard !isRewriting, let _ = episode else { return }
        isRewriting = true
        rewriteError = nil
        runningAgentType = "script_rewriter"

        do {
            let stream = APIEndpoints.AgentAPI.chat(
                agentType: "script_rewriter",
                episodeId: episodeId,
                message: "开始改写"
            )
            // Consume the stream to completion
            for try await _ in stream { }
            // Reload episode to get updated script_content
            await reload()
        } catch {
            rewriteError = error.localizedDescription
        }

        isRewriting = false
        runningAgentType = nil
    }

    /// Skip rewrite: copy raw content directly to script_content.
    func skipRewrite() async {
        guard let content = episode?.content else { return }
        await saveRewriteContent(content)
    }

    /// Re-run rewrite (same as runRewrite).
    func rewriteAgain() async {
        await runRewrite()
    }

    // MARK: - Extract Characters/Scenes (E7.2)

    /// Trigger character/scene extraction via extractor agent.
    func runExtract() async {
        guard !isExtracting else { return }
        isExtracting = true
        extractError = nil
        runningAgentType = "extractor"

        do {
            let stream = APIEndpoints.AgentAPI.chat(
                agentType: "extractor",
                episodeId: episodeId,
                message: "开始提取"
            )
            for try await _ in stream { }
            // Reload characters and scenes
            async let fetchedCharacters = APIEndpoints.EpisodeAPI.characters(episodeId: episodeId)
            async let fetchedScenes = APIEndpoints.EpisodeAPI.scenes(episodeId: episodeId)
            let (chars, scns) = try await (fetchedCharacters, fetchedScenes)
            self.characters = chars
            self.scenes = scns
        } catch {
            extractError = error.localizedDescription
        }

        isExtracting = false
        runningAgentType = nil
    }

    // MARK: - Voice Assignment (E8)

    /// Trigger voice assignment via voice_assigner agent.
    func runVoiceAssignment() async {
        guard !isAssigningVoices else { return }
        isAssigningVoices = true
        voiceAssignError = nil
        runningAgentType = "voice_assigner"

        do {
            let stream = APIEndpoints.AgentAPI.chat(
                agentType: "voice_assigner",
                episodeId: episodeId,
                message: "开始分配音色"
            )
            for try await _ in stream { }
            characters = try await APIEndpoints.EpisodeAPI.characters(episodeId: episodeId)
        } catch {
            voiceAssignError = error.localizedDescription
        }

        isAssigningVoices = false
        runningAgentType = nil
    }

    // MARK: - Storyboard Breakdown (E9)

    /// Trigger storyboard breakdown via storyboard_breaker agent.
    func runStoryboardBreakdown() async {
        guard !isBreakingStoryboard else { return }
        isBreakingStoryboard = true
        storyboardBreakError = nil
        runningAgentType = "storyboard_breaker"

        do {
            let stream = APIEndpoints.AgentAPI.chat(
                agentType: "storyboard_breaker",
                episodeId: episodeId,
                message: "开始拆解分镜"
            )
            for try await _ in stream { }
            storyboards = try await APIEndpoints.EpisodeAPI.storyboards(episodeId: episodeId)
        } catch {
            storyboardBreakError = error.localizedDescription
        }

        isBreakingStoryboard = false
        runningAgentType = nil
    }

    // MARK: - Storyboard Management (E10)

    /// 重新从后端加载分镜列表。
    func loadStoryboards() async {
        do {
            storyboards = try await APIEndpoints.EpisodeAPI.storyboards(episodeId: episodeId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 添加一个新的空白分镜。
    func addStoryboard() async {
        do {
            // 计算下一个分镜编号
            let nextNumber = (storyboards.map(\.storyboardNumber).max() ?? 0) + 1
            let request = CreateStoryboardRequest(
                episodeId: episodeId,
                storyboardNumber: nextNumber
            )
            _ = try await APIEndpoints.StoryboardAPI.create(request)
            // 创建后刷新列表
            await loadStoryboards()
        } catch {
            storyboardBreakError = error.localizedDescription
        }
    }

    // MARK: - Voice Profiles (E8)

    /// Load available voice profiles from the backend.
    func loadVoiceProfiles() async {
        guard !isLoadingVoices else { return }
        isLoadingVoices = true
        do {
            voiceProfiles = try await APIEndpoints.VoicesAPI.list()
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingVoices = false
    }

    // MARK: - Character Voice Update

    /// Update a character's voice style locally and persist to the backend.
    func updateCharacterVoice(characterId: Int, voiceStyle: String) async {
        guard let idx = characters.firstIndex(where: { $0.id == characterId }) else { return }
        characters[idx].voiceStyle = voiceStyle
        do {
            _ = try await APIEndpoints.DramaAPI.saveCharacters(dramaId: dramaId, characters: characters)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Production State (E10)

    // 角色图片生成
    @Published var pendingCharacterImageIds: Set<Int> = []
    @Published var isBatchGeneratingCharacterImages = false

    // 场景图片生成
    @Published var pendingSceneImageIds: Set<Int> = []
    @Published var isBatchGeneratingSceneImages = false

    // TTS 配音生成
    @Published var pendingTTSStoryboardIds: Set<Int> = []
    @Published var isBatchGeneratingTTS = false

    // 镜头图片生成
    @Published var pendingShotImageIds: Set<Int> = []
    @Published var isBatchGeneratingShotImages = false

    // 视频生成
    @Published var pendingVideoStoryboardIds: Set<Int> = []
    @Published var isBatchGeneratingVideos = false

    // 视频合成
    @Published var pendingComposeIds: Set<Int> = []
    @Published var isBatchComposing = false

    // 合并
    @Published var isMerging = false
    @Published var mergedVideoUrl: String?
    @Published var mergeError: String?

    // MARK: - Pipeline Status Polling (E10)

    /// Fetch current pipeline status from the backend.
    func pollPipelineStatus() async -> PipelineStatus {
        do {
            return try await APIEndpoints.EpisodeAPI.pipelineStatus(episodeId: episodeId)
        } catch {
            self.error = error.localizedDescription
            // Return a dummy status on error
            return PipelineStatus(
                episodeId: episodeId,
                steps: PipelineSteps(
                    scriptRewrite: StepInfo(status: "unknown"),
                    extractCharacters: StepInfo(status: "unknown"),
                    extractScenes: StepInfo(status: "unknown"),
                    assignVoices: StepInfo(status: "unknown"),
                    generateVoiceSamples: StepInfo(status: "unknown"),
                    extractStoryboards: StepInfo(status: "unknown"),
                    generateImages: StepInfo(status: "unknown"),
                    generateVideos: StepInfo(status: "unknown"),
                    composeShots: StepInfo(status: "unknown"),
                    mergeEpisode: StepInfo(status: "unknown")
                )
            )
        }
    }

    /// Poll pipeline status until a specific step reaches a terminal state.
    private func pollUntilCompleted(
        stepKeyPath: KeyPath<PipelineSteps, StepInfo>,
        timeout: TimeInterval = 300,
        interval: TimeInterval = 3
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let status = await pollPipelineStatus()
            let stepInfo = status.steps[keyPath: stepKeyPath]
            if stepInfo.status == "completed" || stepInfo.status == "done" {
                return
            }
            if stepInfo.status == "failed" {
                throw NSError(domain: "StudioViewModel", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Pipeline step failed"
                ])
            }
            try await Task.sleep(for: .seconds(interval))
        }
        throw NSError(domain: "StudioViewModel", code: -2, userInfo: [
            NSLocalizedDescriptionKey: "Pipeline step timed out"
        ])
    }

    // MARK: - Single Generation Methods (E10)

    /// Generate character image for a single character.
    func generateCharacterImage(characterId: Int) async {
        pendingCharacterImageIds.insert(characterId)
        defer { pendingCharacterImageIds.remove(characterId) }

        do {
            let request = GenerateCharacterImageRequest(characterId: characterId)
            try await APIEndpoints.ImagesAPI.generateCharacter(request)
            // Poll until image generation for this character is done
            try await pollUntilCompleted(stepKeyPath: \.generateImages)
            // Refresh characters to pick up new imageUrl
            characters = try await APIEndpoints.EpisodeAPI.characters(episodeId: episodeId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Generate scene image for a single scene.
    func generateSceneImage(sceneId: Int) async {
        pendingSceneImageIds.insert(sceneId)
        defer { pendingSceneImageIds.remove(sceneId) }

        do {
            try await APIEndpoints.ImagesAPI.generateScene(sceneId: sceneId)
            try await pollUntilCompleted(stepKeyPath: \.generateImages)
            scenes = try await APIEndpoints.EpisodeAPI.scenes(episodeId: episodeId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Generate TTS dubbing for a single storyboard.
    func generateTTS(storyboardId: Int) async {
        pendingTTSStoryboardIds.insert(storyboardId)
        defer { pendingTTSStoryboardIds.remove(storyboardId) }

        do {
            try await APIEndpoints.ComposeAPI.tts(storyboardId: storyboardId)
            try await pollUntilCompleted(stepKeyPath: \.composeShots)
            storyboards = try await APIEndpoints.EpisodeAPI.storyboards(episodeId: episodeId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Generate shot image (composed_image) for a single storyboard.
    func generateShotImage(storyboardId: Int) async {
        pendingShotImageIds.insert(storyboardId)
        defer { pendingShotImageIds.remove(storyboardId) }

        do {
            let request = GenerateStoryboardImageRequest(storyboardId: storyboardId)
            try await APIEndpoints.ImagesAPI.generateStoryboard(request)
            try await pollUntilCompleted(stepKeyPath: \.generateImages)
            storyboards = try await APIEndpoints.EpisodeAPI.storyboards(episodeId: episodeId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Generate video for a single storyboard.
    func generateVideo(storyboardId: Int) async {
        pendingVideoStoryboardIds.insert(storyboardId)
        defer { pendingVideoStoryboardIds.remove(storyboardId) }

        do {
            try await APIEndpoints.VideosAPI.generate(storyboardId: storyboardId)
            try await pollUntilCompleted(stepKeyPath: \.generateVideos)
            storyboards = try await APIEndpoints.EpisodeAPI.storyboards(episodeId: episodeId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Compose shot (video + audio) for a single storyboard.
    func composeShot(storyboardId: Int) async {
        pendingComposeIds.insert(storyboardId)
        defer { pendingComposeIds.remove(storyboardId) }

        do {
            try await APIEndpoints.ComposeAPI.shot(storyboardId: storyboardId)
            try await pollUntilCompleted(stepKeyPath: \.composeShots)
            storyboards = try await APIEndpoints.EpisodeAPI.storyboards(episodeId: episodeId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Batch Generation Methods (E10)

    /// Batch generate character images for all characters missing an image.
    func batchGenerateCharacterImages() async {
        guard !isBatchGeneratingCharacterImages else { return }
        isBatchGeneratingCharacterImages = true
        defer { isBatchGeneratingCharacterImages = false }

        let targets = characters.filter { $0.imageUrl == nil || $0.imageUrl!.isEmpty }
        await withTaskGroup(of: Void.self) { group in
            for character in targets {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.generateCharacterImage(characterId: character.id)
                }
            }
        }
    }

    /// Batch generate scene images for all scenes missing an image.
    func batchGenerateSceneImages() async {
        guard !isBatchGeneratingSceneImages else { return }
        isBatchGeneratingSceneImages = true
        defer { isBatchGeneratingSceneImages = false }

        let targets = scenes.filter { $0.imageUrl == nil || $0.imageUrl!.isEmpty }
        await withTaskGroup(of: Void.self) { group in
            for scene in targets {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.generateSceneImage(sceneId: scene.id)
                }
            }
        }
    }

    /// Batch generate TTS for all storyboards with dialogue but no audio.
    func batchGenerateTTS() async {
        guard !isBatchGeneratingTTS else { return }
        isBatchGeneratingTTS = true
        defer { isBatchGeneratingTTS = false }

        let targets = storyboardsWithDialogue.filter { $0.ttsAudioUrl == nil || $0.ttsAudioUrl!.isEmpty }
        await withTaskGroup(of: Void.self) { group in
            for storyboard in targets {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.generateTTS(storyboardId: storyboard.id)
                }
            }
        }
    }

    /// Batch generate shot images for all storyboards missing a composed image.
    func batchGenerateShotImages() async {
        guard !isBatchGeneratingShotImages else { return }
        isBatchGeneratingShotImages = true
        defer { isBatchGeneratingShotImages = false }

        let targets = storyboards.filter { $0.composedImage == nil || $0.composedImage!.isEmpty }
        await withTaskGroup(of: Void.self) { group in
            for storyboard in targets {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.generateShotImage(storyboardId: storyboard.id)
                }
            }
        }
    }

    /// Batch generate videos for all storyboards with images but no video.
    func batchGenerateVideos() async {
        guard !isBatchGeneratingVideos else { return }
        isBatchGeneratingVideos = true
        defer { isBatchGeneratingVideos = false }

        let targets = storyboardsWithComposedImage.filter { $0.videoUrl == nil || $0.videoUrl!.isEmpty }
        await withTaskGroup(of: Void.self) { group in
            for storyboard in targets {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.generateVideo(storyboardId: storyboard.id)
                }
            }
        }
    }

    /// Batch compose shots for all storyboards with video but no composed video.
    func batchComposeShots() async {
        guard !isBatchComposing else { return }
        isBatchComposing = true
        defer { isBatchComposing = false }

        let targets = storyboards.filter { sb in
            guard let videoUrl = sb.videoUrl, !videoUrl.isEmpty else { return false }
            return sb.composedVideoUrl == nil || sb.composedVideoUrl!.isEmpty
        }
        await withTaskGroup(of: Void.self) { group in
            for storyboard in targets {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.composeShot(storyboardId: storyboard.id)
                }
            }
        }
    }

    // MARK: - Merge Episode (E10)

    /// Merge all composed shots into a single episode video.
    func mergeEpisode() async {
        guard !isMerging else { return }
        isMerging = true
        mergeError = nil
        mergedVideoUrl = nil

        do {
            try await APIEndpoints.MergeAPI.episode(episodeId: episodeId)
            // Poll until merge completes and mergedUrl appears
            let deadline = Date().addingTimeInterval(600) // 10 min timeout for merge
            while Date() < deadline {
                let pipeline = try await APIEndpoints.EpisodeAPI.pipelineStatus(episodeId: episodeId)
                let mergeStep = pipeline.steps.mergeEpisode
                if mergeStep.status == "completed" || mergeStep.status == "done" {
                    if let url = mergeStep.mergedUrl, !url.isEmpty {
                        mergedVideoUrl = url
                    }
                    break
                }
                if mergeStep.status == "failed" {
                    throw NSError(domain: "StudioViewModel", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "视频合并失败"
                    ])
                }
                try await Task.sleep(for: .seconds(3))
            }
            // Reload episode to pick up videoUrl
            await reload()
        } catch {
            mergeError = error.localizedDescription
        }

        isMerging = false
    }

    // MARK: - Production Computed Properties (E10)

    /// Storyboards that have a composed image.
    var storyboardsWithComposedImage: [Storyboard] {
        storyboards.filter { sb in
            guard let image = sb.composedImage else { return false }
            return !image.isEmpty
        }
    }

    /// Storyboards that have dialogue (need TTS).
    var storyboardsWithDialogue: [Storyboard] {
        storyboards.filter { sb in
            guard let dialogue = sb.dialogue else { return false }
            return !dialogue.isEmpty
        }
    }

    /// Number of storyboards with composed video.
    var composedCount: Int {
        storyboards.filter { sb in
            sb.composedVideoUrl != nil && !sb.composedVideoUrl!.isEmpty
        }.count
    }

    /// Number of storyboards ready for export (composed video done).
    var exportReadyCount: Int {
        storyboards.filter { sb in
            sb.composedVideoUrl != nil && !sb.composedVideoUrl!.isEmpty
        }.count
    }
}
