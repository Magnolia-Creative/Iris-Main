internal import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var loadErrorMessage: String?
    @Published private(set) var deleteProjectErrorMessage: String?
    @Published var isPresentingProjectSetup = false
    @Published var isPresentingProfile = false
    @Published var isPresentingComponentShowcase = false
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

    func presentComponentShowcase() {
        isPresentingComponentShowcase = true
    }

    func returnHomeFromEditor() {
        selectedProject = nil
        isPresentingProjectSetup = false
    }

    func presentProfile() {
        isPresentingProfile = true
    }

    func dismissProfile() {
        isPresentingProfile = false
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

    func deleteProject(_ project: Project) {
        deleteProjectErrorMessage = nil
        ProjectCoverService.shared.removeStoredCover(
            forProjectId: project.projectId,
            coverImagePath: project.coverImagePath
        )
        do {
            try db.delete(Project.self, id: project.projectId, keyColumn: "project_id")
            projects.removeAll { $0.projectId == project.projectId }
            if selectedProject?.projectId == project.projectId {
                selectedProject = nil
            }
        } catch {
            deleteProjectErrorMessage = "Could not delete project."
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
