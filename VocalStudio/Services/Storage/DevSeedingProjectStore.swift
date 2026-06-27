import Foundation

#if DEBUG
/// Decorates a real store so the simulator always has one project to work with,
/// without a manual import every run. Reads the seed audio straight off the source
/// tree via `#filePath` — the file lives outside the synchronized target group
/// (see DevAssets/ at the repo root), so it can never end up in a shipped bundle.
/// This type only compiles in Debug; Release always uses the wrapped store directly.
final class DevSeedingProjectStore: ProjectStoreInterface {
    private let wrapped: ProjectStoreInterface
    private var hasAttemptedSeed = false

    init(wrapping wrapped: ProjectStoreInterface) {
        self.wrapped = wrapped
    }

    func loadAll() async throws -> [Project] {
        var projects = try await wrapped.loadAll()
        if !hasAttemptedSeed && projects.isEmpty {
            hasAttemptedSeed = true
            if let seed = Self.makeSeedProject() {
                try await wrapped.save(seed)
                projects = [seed]
            }
        }
        return projects
    }

    func save(_ project: Project) async throws {
        try await wrapped.save(project)
    }

    func delete(id: UUID) async throws {
        try await wrapped.delete(id: id)
    }

    // MARK: - Seed source

    private static func makeSeedProject() -> Project? {
        let seedURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Storage/
            .deletingLastPathComponent()  // Services/
            .deletingLastPathComponent()  // VocalStudio/
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("DevAssets/dev_seed_track.mp3")

        guard FileManager.default.fileExists(atPath: seedURL.path) else { return nil }
        return Project(title: "Arcade (cover)", sourceURL: seedURL)
    }
}
#endif
