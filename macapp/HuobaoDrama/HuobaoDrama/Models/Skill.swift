import Foundation

struct Skill: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var description: String
    var content: String?
}
