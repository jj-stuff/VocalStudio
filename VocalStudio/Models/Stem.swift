import Foundation

struct Stem: Identifiable, Codable {
    enum Kind: String, Codable {
        case vocal
        case instrumental
    }

    let id: UUID
    let kind: Kind
    let url: URL
    let isMuted: Bool

    func toggled() -> Stem {
        Stem(id: id, kind: kind, url: url, isMuted: !isMuted)
    }
}
