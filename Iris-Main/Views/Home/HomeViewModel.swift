internal import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var loadErrorMessage: String?
    @Published var isPresentingProjectSetup = false
    @Published var selectedProject: Project?

    private let db: DatabaseManager

    init(db: DatabaseManager? = nil) {
        self.db = db ?? .shared
    }

    var recentProjects: [Project] {
        Array(sortedProjects.prefix(5))
    }

    var allProjects: [Project] {
        sortedProjects
    }

    func loadProjects() {
        do {
            projects = try db.getAll(Project.self)
            loadErrorMessage = nil
        } catch {
            projects = []
            loadErrorMessage = "Failed to load projects."
        }
    }

    func presentProjectSetup() {
        isPresentingProjectSetup = true
    }

    func openProject(_ project: Project) {
        var updatedProject = project
        updatedProject.lastAccessedAt = Date()

        do {
            try db.update(updatedProject)
            replaceProject(updatedProject)
            selectedProject = updatedProject
        } catch {
            selectedProject = project
        }
    }

    private var sortedProjects: [Project] {
        projects.sorted { lhs, rhs in
            if lhs.primaryTimestamp == rhs.primaryTimestamp {
                if lhs.createdAt == rhs.createdAt {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.primaryTimestamp > rhs.primaryTimestamp
        }
    }

    private func replaceProject(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.projectId == project.projectId }) else {
            projects.insert(project, at: 0)
            return
        }
        projects[index] = project
    }
}
