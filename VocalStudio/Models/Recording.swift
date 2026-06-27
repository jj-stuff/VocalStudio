import Foundation

struct Recording: Identifiable, Codable {
    let id: UUID
    let url: URL
    let createdAt: Date

    init(id: UUID = UUID(), url: URL, createdAt: Date = .now) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
    }
}
