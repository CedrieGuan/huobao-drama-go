import Foundation

enum SettingsTab: String, CaseIterable {
    case ai
    case agents
    case skills
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var selectedTab: SettingsTab = .ai
    @Published var showAdvanced = false
    @Published var isLoading = false
    @Published var error: String?

    // AI Service Configs
    @Published var aiConfigs: [AIServiceConfig] = []
    @Published var aiProviders: [AIServiceProvider] = []

    // Agent Configs
    @Published var agentConfigs: [AgentConfig] = []

    // Skills
    @Published var skills: [Skill] = []
    @Published var selectedAgentType: String?

    func load() async {
        isLoading = true
        error = nil
        do {
            async let configs = APIEndpoints.AIConfigAPI.list()
            async let providers = APIEndpoints.AIConfigAPI.providers()
            async let agents = APIEndpoints.AgentConfigAPI.list()
            async let skillList = APIEndpoints.SkillsAPI.list()
            let (c, p, a, s) = try await (configs, providers, agents, skillList)
            aiConfigs = c
            aiProviders = p
            agentConfigs = a
            skills = s
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    var baseTabs: [SettingsTab] {
        [.ai]
    }

    var advancedTabs: [SettingsTab] {
        [.agents, .skills]
    }
}
