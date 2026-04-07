import SwiftUI

struct HomeView: View {
    @State private var projects: [Project] = []
    @State private var navigateToSetup = false
    @State private var selectedProject: Project?
    private let columns = [GridItem(.adaptive(minimum: 160), spacing: .spacing(.sp4))]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ds.bg.ignoresSafeArea()

                ScrollView {
                    LazyVGrid(columns: columns, spacing: .spacing(.sp4)) {
                        newProjectCard

                        ForEach(projects) { project in
                            projectCard(project)
                        }
                    }
                    .padding(.horizontal, .sp6)
                    .padding(.vertical, .sp8)
                }
            }
            .navigationTitle("Iris")
            .navigationDestination(isPresented: $navigateToSetup) {
                ProjectSetupView()
            }
            .navigationDestination(item: $selectedProject) { project in
                editorDestination(for: project)
            }
            .task { loadProjects() }
        }
    }

    private var newProjectCard: some View {
        Button { navigateToSetup = true } label: {
            VStack(spacing: .spacing(.sp3)) {
                RoundedRectangle(cornerRadius: .spacing(.sp3))
                    .fill(Color.ds.surface)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(Color.ds.accentFg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: .spacing(.sp3))
                            .strokeBorder(Color.ds.accentFg.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [8]))
                    )

                Text("New Project")
                    .typography(.body)
                    .foregroundColor(Color.ds.text)
            }
        }
        .buttonStyle(.plain)
    }

    private func projectCard(_ project: Project) -> some View {
        Button { selectedProject = project } label: {
            VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                RoundedRectangle(cornerRadius: .spacing(.sp3))
                    .fill(Color.ds.surface)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay(
                        Image(systemName: "film.stack")
                            .font(.system(size: 24))
                            .foregroundColor(Color.ds.textMuted)
                    )

                Text(project.name)
                    .typography(.body)
                    .foregroundColor(Color.ds.text)
                    .lineLimit(1)

                Text(project.updatedAt.formatted(.relative(presentation: .named)))
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.textMuted)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func editorDestination(for project: Project) -> some View {
        if let timeline = try? DatabaseManager.shared.getTimeline(forProjectId: project.projectId) {
            EditorContainerView(timelineId: timeline.timelineId)
        } else {
            Text("No timeline found")
                .foregroundColor(Color.ds.textMuted)
        }
    }

    private func loadProjects() {
        do {
            projects = try DatabaseManager.shared.getAll(Project.self)
        } catch {
            print("Failed to load projects: \(error)")
        }
    }
}

extension Project: @retroactive Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(projectId)
    }

    static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.projectId == rhs.projectId
    }
}
