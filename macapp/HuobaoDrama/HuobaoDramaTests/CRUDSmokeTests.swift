import Foundation
import Testing
@testable import HuobaoDrama

/// A21.2 — Drama / Episode CRUD Smoke Tests
///
/// Tests that the Swift models can decode real API responses from the Go backend.
/// These tests use hardcoded JSON samples captured from the running backend-go (port 5680)
/// to ensure the model decoding matches the actual wire format without requiring
/// a live backend during CI.
///
/// To run against a live backend, start `backend-go` on port 5680 and set
/// ConnectionSettingsStore.shared.baseURL to "http://localhost:5680".
@Suite("A21.2 CRUD Smoke Tests")
struct CRUDSmokeTests {

    // MARK: - Drama List (Paginated)

    @Test("Drama list decodes from paginated API response")
    func dramaListDecode() throws {
        let json = """
        {
            "code": 200,
            "data": {
                "items": [
                    {
                        "id": 1,
                        "title": "测试剧本",
                        "description": null,
                        "genre": "drama",
                        "style": "realistic",
                        "total_episodes": 2,
                        "total_duration": 0,
                        "status": "draft",
                        "thumbnail": null,
                        "tags": ["热血"],
                        "metadata": null,
                        "created_at": "2026-04-25T10:00:00Z",
                        "updated_at": "2026-04-25T10:00:00Z",
                        "deleted_at": null,
                        "episodes": [
                            {
                                "id": 10,
                                "drama_id": 1,
                                "episode_number": 1,
                                "title": "第1集",
                                "content": null,
                                "script_content": null,
                                "description": null,
                                "duration": 0,
                                "status": "draft",
                                "video_url": null,
                                "thumbnail": null,
                                "image_config_id": null,
                                "video_config_id": null,
                                "audio_config_id": null,
                                "created_at": "2026-04-25T10:00:00Z",
                                "updated_at": "2026-04-25T10:00:00Z",
                                "deleted_at": null
                            }
                        ],
                        "characters": [],
                        "scenes": []
                    }
                ],
                "pagination": {
                    "page": 1,
                    "page_size": 20,
                    "total": 1,
                    "total_pages": 1
                }
            },
            "message": "success"
        }
        """
        let response = try JSONDecoder().decode(APIResponse<PaginatedResponse<Drama>>.self, from: Data(json.utf8))
        #expect(response.code == 200)
        #expect(response.data != nil)
        let page = try #require(response.data)
        #expect(page.items.count == 1)
        #expect(page.items[0].title == "测试剧本")
        #expect(page.items[0].totalEpisodes == 2)
        #expect(page.items[0].tags == ["热血"])
        #expect(page.items[0].episodes.count == 1)
        #expect(page.pagination.page == 1)
        #expect(page.pagination.total == 1)
    }

    // MARK: - Create Drama

    @Test("Create drama response decodes without episodes/characters/scenes")
    func createDramaDecode() throws {
        // Go backend CreateDrama returns the raw Drama struct without enrichment.
        // Swift Drama model uses decodeIfPresent for episodes/characters/scenes.
        let json = """
        {
            "code": 201,
            "data": {
                "id": 2,
                "title": "新剧本",
                "description": null,
                "genre": null,
                "style": "realistic",
                "total_episodes": 1,
                "total_duration": 0,
                "status": "draft",
                "thumbnail": null,
                "tags": null,
                "metadata": null,
                "created_at": "2026-04-25T10:30:00Z",
                "updated_at": "2026-04-25T10:30:00Z",
                "deleted_at": null
            },
            "message": "created"
        }
        """
        let response = try JSONDecoder().decode(APIResponse<Drama>.self, from: Data(json.utf8))
        #expect(response.code == 201)
        let drama = try #require(response.data)
        #expect(drama.id == 2)
        #expect(drama.title == "新剧本")
        #expect(drama.episodes.isEmpty)  // defaults to [] via decodeIfPresent
        #expect(drama.characters.isEmpty)
        #expect(drama.scenes.isEmpty)
        #expect(drama.tags.isEmpty)      // null → [] via decodeIfPresent
    }

    // MARK: - Get Drama Detail (enriched)

    @Test("Get drama detail decodes with full enrichment")
    func getDramaDetailDecode() throws {
        let json = """
        {
            "code": 200,
            "data": {
                "id": 1,
                "title": "详情剧本",
                "description": "一段描述",
                "genre": "drama",
                "style": "realistic",
                "total_episodes": 1,
                "total_duration": 0,
                "status": "draft",
                "thumbnail": null,
                "tags": [],
                "metadata": null,
                "created_at": "2026-04-25T10:00:00Z",
                "updated_at": "2026-04-25T10:00:00Z",
                "deleted_at": null,
                "episodes": [
                    {
                        "id": 10,
                        "drama_id": 1,
                        "episode_number": 1,
                        "title": "第1集",
                        "content": null,
                        "script_content": null,
                        "description": null,
                        "duration": 0,
                        "status": "draft",
                        "video_url": null,
                        "thumbnail": null,
                        "image_config_id": null,
                        "video_config_id": null,
                        "audio_config_id": null,
                        "created_at": "2026-04-25T10:00:00Z",
                        "updated_at": "2026-04-25T10:00:00Z",
                        "deleted_at": null
                    }
                ],
                "characters": [],
                "scenes": []
            },
            "message": "success"
        }
        """
        let response = try JSONDecoder().decode(APIResponse<Drama>.self, from: Data(json.utf8))
        let drama = try #require(response.data)
        #expect(drama.episodes.count == 1)
        #expect(drama.episodes[0].episodeLabel == "E01")
        #expect(drama.description == "一段描述")
    }

    // MARK: - Create Episode (full response after fix)

    @Test("Create episode response decodes with all required fields")
    func createEpisodeDecode() throws {
        // After fix: Go backend now returns full episode data including
        // drama_id, status, created_at, updated_at — all required by Swift Episode model.
        let json = """
        {
            "code": 201,
            "data": {
                "id": 15,
                "drama_id": 1,
                "episode_number": 2,
                "title": "烟测集",
                "content": null,
                "script_content": null,
                "description": null,
                "duration": 0,
                "status": "draft",
                "video_url": null,
                "thumbnail": null,
                "image_config_id": 1,
                "video_config_id": 1,
                "audio_config_id": 1,
                "created_at": "2026-04-25T10:33:48Z",
                "updated_at": "2026-04-25T10:33:48Z"
            },
            "message": "created"
        }
        """
        let response = try JSONDecoder().decode(APIResponse<Episode>.self, from: Data(json.utf8))
        #expect(response.code == 201)
        let ep = try #require(response.data)
        #expect(ep.id == 15)
        #expect(ep.dramaId == 1)
        #expect(ep.episodeNumber == 2)
        #expect(ep.title == "烟测集")
        #expect(ep.status == "draft")
        #expect(ep.duration == 0)
        #expect(ep.imageConfigId == 1)
        #expect(ep.createdAt == "2026-04-25T10:33:48Z")
        #expect(ep.updatedAt == "2026-04-25T10:33:48Z")
    }

    // MARK: - Pipeline Status

    @Test("Pipeline status decodes from API response")
    func pipelineStatusDecode() throws {
        let json = """
        {
            "code": 200,
            "data": {
                "episode_id": 10,
                "steps": {
                    "script_rewrite": { "status": "pending" },
                    "extract_characters": { "status": "pending", "count": 0 },
                    "extract_scenes": { "status": "pending", "count": 0 },
                    "assign_voices": { "status": "pending", "assigned": 0, "total": 0 },
                    "generate_voice_samples": { "status": "pending", "completed": 0, "total": 0 },
                    "extract_storyboards": { "status": "pending", "count": 0 },
                    "generate_images": { "status": "pending", "completed": 0, "total": 0 },
                    "generate_videos": { "status": "pending", "completed": 0, "total": 0 },
                    "compose_shots": { "status": "pending", "completed": 0, "total": 0 },
                    "merge_episode": { "status": "pending", "merged_url": null }
                }
            },
            "message": "success"
        }
        """
        let response = try JSONDecoder().decode(APIResponse<PipelineStatus>.self, from: Data(json.utf8))
        let ps = try #require(response.data)
        #expect(ps.episodeId == 10)
        #expect(ps.steps.scriptRewrite.status == "pending")
        #expect(ps.steps.extractCharacters.count == 0)
        #expect(ps.steps.assignVoices.assigned == 0)
        #expect(ps.steps.mergeEpisode.mergedUrl == nil)
    }

    // MARK: - Drama Stats

    @Test("Drama stats decodes from API response")
    func dramaStatsDecode() throws {
        let json = """
        {
            "code": 200,
            "data": {
                "total": 2,
                "by_status": [
                    { "status": "draft", "count": 2 }
                ]
            },
            "message": "success"
        }
        """
        // DramaStats returns a generic dict, just verify the envelope structure
        let response = try JSONDecoder().decode(APIResponse<StatsData>.self, from: Data(json.utf8))
        #expect(response.code == 200)
        let data = try #require(response.data)
        #expect(data.total == 2)
    }

    // MARK: - Empty list response

    @Test("Empty list response decodes correctly")
    func emptyListDecode() throws {
        let json = """
        {
            "code": 200,
            "data": {
                "items": [],
                "pagination": {
                    "page": 1,
                    "page_size": 20,
                    "total": 0,
                    "total_pages": 0
                }
            },
            "message": "success"
        }
        """
        let response = try JSONDecoder().decode(APIResponse<PaginatedResponse<Drama>>.self, from: Data(json.utf8))
        let page = try #require(response.data)
        #expect(page.items.isEmpty)
        #expect(page.pagination.total == 0)
    }

    // MARK: - Episode sub-resources (empty arrays)

    @Test("Episode characters empty array decodes")
    func episodeCharactersEmptyDecode() throws {
        let json = """
        {
            "code": 200,
            "data": [],
            "message": "success"
        }
        """
        let response = try JSONDecoder().decode(APIResponse<[Character]>.self, from: Data(json.utf8))
        let chars = try #require(response.data)
        #expect(chars.isEmpty)
    }

    @Test("Episode storyboards empty array decodes")
    func episodeStoryboardsEmptyDecode() throws {
        let json = """
        {
            "code": 200,
            "data": [],
            "message": "success"
        }
        """
        let response = try JSONDecoder().decode(APIResponse<[Storyboard]>.self, from: Data(json.utf8))
        let sbs = try #require(response.data)
        #expect(sbs.isEmpty)
    }

    // MARK: - Delete / Success responses

    @Test("Delete drama success response decodes")
    func deleteDramaDecode() throws {
        let json = """
        {
            "code": 200,
            "message": "success"
        }
        """
        let response = try JSONDecoder().decode(APIResponse<EmptyData>.self, from: Data(json.utf8))
        #expect(response.code == 200)
    }
}

// Helper type for drama stats decoding
private struct StatsData: Decodable, Sendable {
    let total: Int
    let byStatus: [StatusCount]
    enum CodingKeys: String, CodingKey {
        case total
        case byStatus = "by_status"
    }
}

private struct StatusCount: Decodable, Sendable {
    let status: String
    let count: Int
}
