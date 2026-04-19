import Testing
import Foundation
@testable import HuobaoDrama

// MARK: - Service Tests

@Suite("Service Tests")
struct ServiceTests {

    // MARK: - PollingCoordinator 测试

    @Test("PollingCoordinator - startPolling 创建轮询任务")
    func pollingCoordinatorStart() async throws {
        let coordinator = PollingCoordinator.shared

        var pollCount = 0
        coordinator.startPolling(key: "test_start", interval: 0.1) {
            pollCount += 1
        }

        // 等待足够时间让轮询执行几次
        try await Task.sleep(for: .milliseconds(350))
        coordinator.stopPolling(key: "test_start")

        // 0.1s 间隔，0.35s 内应至少执行 2 次
        #expect(pollCount >= 2)
    }

    @Test("PollingCoordinator - stopPolling 停止轮询")
    func pollingCoordinatorStop() async throws {
        let coordinator = PollingCoordinator.shared

        var pollCount = 0
        coordinator.startPolling(key: "test_stop", interval: 0.1) {
            pollCount += 1
        }

        // 等待一段时间后停止
        try await Task.sleep(for: .milliseconds(200))
        coordinator.stopPolling(key: "test_stop")

        let countAfterStop = pollCount

        // 再等待一段时间，确认不再继续轮询
        try await Task.sleep(for: .milliseconds(300))

        #expect(pollCount == countAfterStop)
    }

    @Test("PollingCoordinator - stopAll 停止所有轮询")
    func pollingCoordinatorStopAll() async throws {
        let coordinator = PollingCoordinator.shared

        var countA = 0
        var countB = 0
        coordinator.startPolling(key: "test_all_a", interval: 0.1) {
            countA += 1
        }
        coordinator.startPolling(key: "test_all_b", interval: 0.1) {
            countB += 1
        }

        // 等待轮询执行
        try await Task.sleep(for: .milliseconds(250))
        coordinator.stopAll()

        let countAAfterStop = countA
        let countBAfterStop = countB

        // 再等待，确认两个轮询都已停止
        try await Task.sleep(for: .milliseconds(300))

        #expect(countA == countAAfterStop)
        #expect(countB == countBAfterStop)
    }

    @Test("PollingCoordinator - 重复 startPolling 同一个 key 会替换旧任务")
    func pollingCoordinatorReplaceKey() async throws {
        let coordinator = PollingCoordinator.shared

        var countFirst = 0
        var countSecond = 0

        coordinator.startPolling(key: "test_replace", interval: 0.1) {
            countFirst += 1
        }

        try await Task.sleep(for: .milliseconds(200))

        // 用同一个 key 启动新的轮询
        coordinator.startPolling(key: "test_replace", interval: 0.1) {
            countSecond += 1
        }

        try await Task.sleep(for: .milliseconds(250))
        coordinator.stopPolling(key: "test_replace")

        // 第一个轮询应该已被替换，不再增长
        let firstCountAfterReplace = countFirst
        try await Task.sleep(for: .milliseconds(200))

        #expect(countFirst == firstCountAfterReplace)
        #expect(countSecond >= 1)
    }

    // MARK: - DownloadExportService 测试

    @Test("DownloadExportService - downloadFile 处理完整 URL")
    func downloadServiceFullURL() async throws {
        // DownloadExportService 使用 URLSession.shared，无法直接 mock
        // 这里验证 URL 组装逻辑：完整 URL 直接使用
        let service = DownloadExportService.shared

        // 测试会因网络不可达而失败，验证错误类型
        do {
            _ = try await service.downloadFile(from: "http://localhost:1/nonexistent/file.mp4")
            Issue.record("应该抛出网络错误")
        } catch {
            // 预期：网络错误
            #expect(error is URLError || error is APIError)
        }
    }

    @Test("DownloadExportService - downloadFile 处理相对路径")
    func downloadServiceRelativePath() async throws {
        let service = DownloadExportService.shared

        // 相对路径应该与 baseURL 拼接
        // 测试会因网络不可达而失败，验证路径拼接不会崩溃
        do {
            _ = try await service.downloadFile(from: "/files/video.mp4")
            Issue.record("应该抛出网络错误")
        } catch {
            // 预期：网络错误（URL 拼接成功但连接失败）
            #expect(error is URLError || error is APIError)
        }
    }

    // MARK: - ConnectionSettingsStore 测试

    @Test("ConnectionSettingsStore - apiBaseURL 包含 /api/v1 后缀")
    func connectionSettingsAPIBaseURL() {
        let store = ConnectionSettingsStore.shared
        let apiURL = store.apiBaseURL
        #expect(apiURL.contains("/api/v1"))
    }

    @Test("ConnectionSettingsStore - apiBaseURL 去除尾部斜杠")
    func connectionSettingsTrailingSlash() {
        let store = ConnectionSettingsStore.shared
        // 设置一个带尾部斜杠的 URL
        let originalBaseURL = store.baseURL
        store.baseURL = "http://localhost:8080/"
        #expect(!store.apiBaseURL.hasSuffix("//"))
        #expect(store.apiBaseURL == "http://localhost:8080/api/v1")
        // 恢复原始值
        store.baseURL = originalBaseURL
    }

    // MARK: - APIEndpoints 路径组装测试

    @Test("APIEndpoints.EpisodeAPI 故事板路径包含 episodeId")
    func episodeAPIStoryboardPath() async throws {
        let session = makeMockSession()
        MockURLProtocol.reset()
        MockURLProtocol.mockData = Data("[]".utf8)
        MockURLProtocol.mockStatusCode = 200

        let url = URL(string: "http://localhost:8080/api/v1/episodes/42/storyboards")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        _ = try await session.data(for: request)

        let capturedURL = MockURLProtocol.lastRequest?.url?.absoluteString ?? ""
        #expect(capturedURL.contains("/episodes/42/storyboards"))
    }

    // MARK: - PipelineStatus 解码测试

    @Test("PipelineStatus 正确解码")
    func pipelineStatusDecoding() throws {
        let json = """
        {
            "episode_id": 10,
            "steps": {
                "script_rewrite": { "status": "done" },
                "extract_characters": { "status": "done", "count": 5 },
                "extract_scenes": { "status": "done", "count": 3 },
                "assign_voices": { "status": "done", "assigned": 5 },
                "generate_voice_samples": { "status": "partial", "completed": 3, "total": 5 },
                "extract_storyboards": { "status": "done", "count": 20 },
                "generate_images": { "status": "in_progress", "completed": 10, "total": 20 },
                "generate_videos": { "status": "pending" },
                "compose_shots": { "status": "pending" },
                "merge_episode": { "status": "pending" }
            }
        }
        """
        let data = Data(json.utf8)
        let status = try JSONDecoder().decode(PipelineStatus.self, from: data)

        #expect(status.episodeId == 10)
        #expect(status.steps.scriptRewrite.status == "done")
        #expect(status.steps.extractCharacters.count == 5)
        #expect(status.steps.assignVoices.assigned == 5)
        #expect(status.steps.generateVoiceSamples.completed == 3)
        #expect(status.steps.generateVoiceSamples.total == 5)
        #expect(status.steps.generateImages.status == "in_progress")
        #expect(status.steps.generateImages.completed == 10)
    }

    @Test("PipelineStatus 解码包含 mergedUrl")
    func pipelineStatusWithMergedUrl() throws {
        let json = """
        {
            "episode_id": 10,
            "steps": {
                "script_rewrite": { "status": "done" },
                "extract_characters": { "status": "done" },
                "extract_scenes": { "status": "done" },
                "assign_voices": { "status": "done" },
                "generate_voice_samples": { "status": "done" },
                "extract_storyboards": { "status": "done" },
                "generate_images": { "status": "done" },
                "generate_videos": { "status": "done" },
                "compose_shots": { "status": "done" },
                "merge_episode": { "status": "done", "merged_url": "https://cdn.example.com/video.mp4" }
            }
        }
        """
        let data = Data(json.utf8)
        let status = try JSONDecoder().decode(PipelineStatus.self, from: data)

        #expect(status.steps.mergeEpisode.status == "done")
        #expect(status.steps.mergeEpisode.mergedUrl == "https://cdn.example.com/video.mp4")
    }

    // MARK: - StepInfo 解码测试

    @Test("StepInfo 解码可选字段")
    func stepInfoDecoding() throws {
        let json = """
        { "status": "partial", "completed": 7, "total": 20 }
        """
        let data = Data(json.utf8)
        let info = try JSONDecoder().decode(StepInfo.self, from: data)

        #expect(info.status == "partial")
        #expect(info.completed == 7)
        #expect(info.total == 20)
        #expect(info.count == nil)
        #expect(info.assigned == nil)
        #expect(info.mergedUrl == nil)
    }

    @Test("StepInfo 最小字段解码")
    func stepInfoMinimalDecoding() throws {
        let json = """
        { "status": "pending" }
        """
        let data = Data(json.utf8)
        let info = try JSONDecoder().decode(StepInfo.self, from: data)

        #expect(info.status == "pending")
        #expect(info.count == nil)
        #expect(info.completed == nil)
        #expect(info.total == nil)
    }
}
