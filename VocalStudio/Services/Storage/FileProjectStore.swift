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
        projects.removeAll { $0.id == id }
        try JSONEncoder().encode(projects).write(to: storeURL, options: .atomic)
    }
}
