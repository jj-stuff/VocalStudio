import Foundation

protocol ProjectStoreInterface {
    func loadAll() async throws -> [Project]
    func save(_ project: Project) async throws
    func delete(id: UUID) async throws
}
