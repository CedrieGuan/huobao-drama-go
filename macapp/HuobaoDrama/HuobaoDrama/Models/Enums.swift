import Foundation

enum DramaStatus: String, Codable, CaseIterable {
    case draft, inProduction = "in_production", completed, archived
    var label: String {
        switch self {
        case .draft: return "草稿"
        case .inProduction: return "制作中"
        case .completed: return "已完成"
        case .archived: return "已归档"
        }
    }
}

enum EpisodeStatus: String, Codable, CaseIterable {
    case draft, scriptReady = "script_ready", inProduction = "in_production", completed
    var label: String {
        switch self {
        case .draft: return "草稿"
        case .scriptReady: return "剧本就绪"
        case .inProduction: return "制作中"
        case .completed: return "已完成"
        }
    }
}

enum GenerationStatus: String, Codable, CaseIterable {
    case pending, processing, completed, failed
    var label: String {
        switch self {
        case .pending: return "待处理"
        case .processing: return "处理中"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }
}

enum AIServiceType: String, Codable, CaseIterable {
    case text, image, video, audio
    var label: String {
        switch self {
        case .text: return "文本"
        case .image: return "图片"
        case .video: return "视频"
        case .audio: return "音频"
        }
    }
}

enum AgentType: String, Codable, CaseIterable {
    case scriptRewriter = "script_rewriter"
    case extractor
    case storyboardBreaker = "storyboard_breaker"
    case voiceAssigner = "voice_assigner"
    case gridPromptGenerator = "grid_prompt_generator"

    var label: String {
        switch self {
        case .scriptRewriter: return "剧本改写"
        case .extractor: return "角色场景提取"
        case .storyboardBreaker: return "分镜拆解"
        case .voiceAssigner: return "音色分配"
        case .gridPromptGenerator: return "图片提示词生成"
        }
    }
}

enum PipelineStepStatus: String, Codable {
    case pending, ready, partial, done, failed
}

enum ShotType: String, Codable, CaseIterable {
    case extreme_wide, wide, medium, closeUp = "close_up", extreme_close = "extreme_close"
    var label: String {
        switch self {
        case .extreme_wide: return "大远景"
        case .wide: return "远景"
        case .medium: return "中景"
        case .closeUp: return "近景"
        case .extreme_close: return "特写"
        }
    }
}
