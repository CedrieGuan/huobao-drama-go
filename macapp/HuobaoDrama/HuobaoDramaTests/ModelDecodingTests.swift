import Testing
@testable import HuobaoDrama

@Suite("Model Decoding Tests")
struct ModelDecodingTests {

    @Test("Drama decodes from JSON")
    func dramaDecode() throws {
        let json = """
        {
            "id": 1,
            "title": "测试剧本",
            "genre": "drama",
            "style": "realistic",
            "total_episodes": 3,
            "status": "draft",
            "tags": ["热血", "青春"],
            "created_at": "2026-04-18T10:00:00Z",
            "updated_at": "2026-04-18T10:00:00Z"
        }
        """
        let drama = try JSONDecoder().decode(Drama.self, from: Data(json.utf8))
        #expect(drama.id == 1)
        #expect(drama.title == "测试剧本")
        #expect(drama.totalEpisodes == 3)
        #expect(drama.tags == ["热血", "青春"])
    }

    @Test("Episode decodes from JSON")
    func episodeDecode() throws {
        let json = """
        {
            "id": 10,
            "drama_id": 1,
            "episode_number": 1,
            "title": "第一集",
            "status": "draft",
            "duration": 0,
            "created_at": "2026-04-18T10:00:00Z",
            "updated_at": "2026-04-18T10:00:00Z"
        }
        """
        let ep = try JSONDecoder().decode(Episode.self, from: Data(json.utf8))
        #expect(ep.id == 10)
        #expect(ep.episodeLabel == "E01")
    }

    @Test("AIServiceConfig decodes from JSON")
    func aiConfigDecode() throws {
        let json = """
        {
            "id": 5,
            "service_type": "text",
            "provider": "chatfire",
            "name": "测试配置",
            "base_url": "https://api.example.com",
            "api_key": "sk-test",
            "model": "gpt-4",
            "priority": 100,
            "is_default": false,
            "is_active": true,
            "created_at": "2026-04-18T10:00:00Z",
            "updated_at": "2026-04-18T10:00:00Z"
        }
        """
        let cfg = try JSONDecoder().decode(AIServiceConfig.self, from: Data(json.utf8))
        #expect(cfg.id == 5)
        #expect(cfg.serviceType == "text")
        #expect(cfg.isActive == true)
    }

    @Test("Storyboard decodes from JSON")
    func storyboardDecode() throws {
        let json = """
        {
            "id": 100,
            "episode_id": 10,
            "storyboard_number": 1,
            "status": "pending",
            "duration": 5,
            "character_ids": [1, 2],
            "created_at": "2026-04-18T10:00:00Z",
            "updated_at": "2026-04-18T10:00:00Z"
        }
        """
        let sb = try JSONDecoder().decode(Storyboard.self, from: Data(json.utf8))
        #expect(sb.id == 100)
        #expect(sb.storyboardNumber == 1)
        #expect(sb.characterIds == [1, 2])
        #expect(sb.label == "01")
    }
}
