import Foundation

final class FileProjectStore: ProjectStoreInterface {
    private let storeURL = URL.documentsDirectory.appending(path: "projects.json")

    func loadAll() async throws -> [Project] {
        guard FileManager.default.fileExists(atPath: storeURL.path()) else { return [] }
        let data = try Data(contentsOf: storeURL)
        return try JSONDecoder().decode([Project].self, from: data)
    }

    func save(_ project: Project) async throws {
        var projects = (try? await loadAll()) ?? []
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
        try JSONEncoder().encode(projects).write(to: storeURL, options: .atomic)
    }

    func delete(id: UUID) async throws {
        var projects = (try? await loadAll()) ?? []
        // Each project's source/stem/recording files live under Documents in
        // per-project-unique, UUID-named paths (see ProjectListViewModel.importAudio,
        // SilentAudioFile.make) — never shared across projects — so it's safe to
        // delete them outright once the project itself is gone. Without this, every
        // project deletion silently leaked its audio files to disk forever.
        //
        // The Documents-only guard matters in DEBUG: DevSeedingProjectStore's seed
        // project points sourceURL at a checked-in repo asset (DevAssets/), not a
        // sandboxed copy — deleting that project must never touch the source tree.
        if let project = projects.first(where: { $0.id == id }) {
            let documentsPath = URL.documentsDirectory.path()
            var urls = [project.sourceURL]
            urls.append(contentsOf: project.stems.map(\.url))
            urls.append(contentsOf: project.recordings.map(\.url))
            for url in urls where url.path().hasPrefix(documentsPath) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        projects.removeAll { $0.id == id }
        try JSONEncoder().encode(projects).write(to: storeURL, options: .atomic)
    }
}
