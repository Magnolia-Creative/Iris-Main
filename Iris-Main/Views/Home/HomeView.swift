import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    Color.ds.bg.ignoresSafeArea()

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: .spacing(.sp7)) {
                            heroBanner
                            recentsSection
                            allProjectsSection
                        }
                        .padding(.horizontal, .sp6)
                        .padding(.top, .sp7)
                        .padding(.bottom, .sp7)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $viewModel.isPresentingProjectSetup) {
                ProjectSetupView()
            }
            .navigationDestination(item: $viewModel.selectedProject) { project in
                editorDestination(for: project)
            }
            .onAppear { viewModel.loadProjects() }
        }
    }

    private var heroBanner: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: .spacing(.sp5))
                .fill(
                    LinearGradient(
                        colors: [
                            Color.ds.accentBg,
                            Color.ds.accentBg.opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: .spacing(.sp5))
                        .stroke(Color.ds.accentFg.opacity(0.38), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: .spacing(.sp4)) {
                Text("What will you\ncreate today?")
                    .typography(.heading)
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Start a fresh project below.")
                    .typography(.body)
                    .foregroundStyle(Color.white.opacity(0.82))
                    .frame(maxWidth: 320, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    viewModel.presentProjectSetup()
                } label: {
                    HStack(spacing: .spacing(.sp2)) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))

                        Text("New Project")
                            .typography(.action)
                    }
                    .foregroundStyle(Color.ds.accentBg)
                    .padding(.horizontal, .sp4)
                    .padding(.vertical, .sp3)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                }
                .buttonStyle(.plain)
            }
            .padding(.sp6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 224)
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp4)) {

            if viewModel.recentProjects.isEmpty {
                emptyStateContent(
                    title: "No recent projects yet",
                    subtitle: "Open a project to see it here, or start a new one to begin editing."
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: .spacing(.sp4)) {
                        ForEach(Array(viewModel.recentProjects.enumerated()), id: \.element.projectId) { index, project in
                            Button {
                                viewModel.openProject(project)
                            } label: {
                                VStack(alignment: .leading, spacing: .spacing(.sp3)) {
                                    ProjectCoverImageView(
                                        project: project,
                                        width: 232,
                                        height: 132,
                                        cornerRadius: .spacing(.sp4)
                                    )

                                    VStack(alignment: .leading, spacing: .spacing(.sp1)) {
                                        Text(project.name)
                                            .typography(.body)
                                            .foregroundStyle(Color.ds.text)
                                            .lineLimit(1)

                                        Text(lastOpenedText(for: project))
                                            .typography(.bodySmall)
                                            .foregroundStyle(Color.ds.textMuted)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: 232, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            if index < viewModel.recentProjects.count - 1 {
                                Divider()
                                    .frame(height: 188)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var allProjectsSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp4)) {


            if let loadErrorMessage = viewModel.loadErrorMessage {
                emptyStateContent(title: "Projects unavailable", subtitle: loadErrorMessage)
            } else if viewModel.allProjects.isEmpty {
                emptyStateContent(
                    title: "No projects yet",
                    subtitle: "Create your first project to start building edits and previews."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.allProjects.enumerated()), id: \.element.projectId) { index, project in
                        Button {
                            viewModel.openProject(project)
                        } label: {
                            HStack(spacing: .spacing(.sp4)) {
                                ProjectCoverImageView(
                                    project: project,
                                    width: 112,
                                    height: 64,
                                    cornerRadius: .spacing(.sp3)
                                )

                                VStack(alignment: .leading, spacing: .spacing(.sp1)) {
                                    Text(project.name)
                                        .typography(.body)
                                        .foregroundStyle(Color.ds.text)
                                        .lineLimit(1)

                                    Text(projectDetailText(for: project))
                                        .typography(.bodySmall)
                                        .foregroundStyle(Color.ds.textMuted)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: .spacing(.sp3))

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.ds.textMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, .sp4)
                        }
                        .buttonStyle(.plain)

                        if index < viewModel.allProjects.count - 1 {
                            Divider()
                                .padding(.leading, 128)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp1)) {
            Text(title)
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            Text(subtitle)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
        }
    }

    private func surfaceSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.sp5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ds.surface)
            .overlay {
                RoundedRectangle(cornerRadius: .spacing(.sp4))
                    .stroke(Color.ds.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4)))
    }

    private func emptyStateContent(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text(title)
                .typography(.body)
                .foregroundStyle(Color.ds.text)

            Text(subtitle)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
        }
    }

    private func heroTopInset(for availableHeight: CGFloat) -> CGFloat {
        max(.spacing(.sp6), availableHeight * 0.22)
    }

    private func projectDetailText(for project: Project) -> String {
        "\(project.resolutionLabel) • \(project.frameRate) fps • \(lastOpenedText(for: project))"
    }

    private func lastOpenedText(for project: Project) -> String {
        "Opened \(project.primaryTimestamp.formatted(.relative(presentation: .named)))"
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
}

private struct ProjectCoverImageView: View {
    let project: Project
    var width: CGFloat? = nil
    var height: CGFloat
    var cornerRadius: CGFloat

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [Color.ds.surface, Color.ds.bg],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: .spacing(.sp2)) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 20, weight: .semibold))
                    Text("No Cover")
                        .typography(.bodySmall)
                }
                .foregroundStyle(Color.ds.textMuted)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.ds.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: project.coverImagePath ?? project.projectId) {
            image = await ProjectCoverService.shared.loadCover(for: project)
        }
    }
}
