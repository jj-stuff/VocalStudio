import Foundation

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let sourceURL: URL
    let createdAt: Date
    let stems: [Stem]
    let recordings: [Recording]
    let effects: EffectSettings

    init(
        id: UUID = UUID(),
        title: String,
        sourceURL: URL,
        createdAt: Date = .now,
        stems: [Stem] = [],
        recordings: [Recording] = [],
        effects: EffectSettings = .default
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.createdAt = createdAt
        self.stems = stems
        self.recordings = recordings
        self.effects = effects
    }

    static func == (lhs: Project, rhs: Project) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: - Display

    var subtitleText: String {
        let days = Calendar.current.dateComponents([.day], from: createdAt, to: .now).day ?? 0
        if days == 0 { return "added today" }
        if days == 1 { return "added yesterday" }
        return "added \(days)d ago"
    }

    var relativeAge: String {
        let days = Calendar.current.dateComponents([.day], from: createdAt, to: .now).day ?? 0
        if days == 0 { return "today" }
        if days < 7 { return "\(days)d" }
        if days < 35 { return "\(days / 7)w" }
        return "\(days / 30)mo"
    }

    // MARK: - Mutation (value-copy helpers)

    func withStems(_ stems: [Stem]) -> Project {
        Project(id: id, title: title, sourceURL: sourceURL, createdAt: createdAt,
                stems: stems, recordings: recordings, effects: effects)
    }

    func withRecording(_ recording: Recording) -> Project {
        Project(id: id, title: title, sourceURL: sourceURL, createdAt: createdAt,
                stems: stems, recordings: recordings + [recording], effects: effects)
    }

    func withEffects(_ effects: EffectSettings) -> Project {
        Project(id: id, title: title, sourceURL: sourceURL, createdAt: createdAt,
                stems: stems, recordings: recordings, effects: effects)
    }

    func withTitle(_ title: String) -> Project {
        Project(id: id, title: title, sourceURL: sourceURL, createdAt: createdAt,
                stems: stems, recordings: recordings, effects: effects)
    }

    func withRecordings(_ recordings: [Recording]) -> Project {
        Project(id: id, title: title, sourceURL: sourceURL, createdAt: createdAt,
                stems: stems, recordings: recordings, effects: effects)
    }
}
