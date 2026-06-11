import ClerkKitUI
import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
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
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $viewModel.isPresentingProjectSetup) {
                ProjectSetupView(onReturnHome: viewModel.returnHomeFromEditor)
            }
            .navigationDestination(isPresented: $viewModel.isPresentingComponentShowcase) {
                EditorComponentShowcaseView()
            }
            .navigationDestination(item: $viewModel.selectedProject) { project in
                editorDestination(for: project)
            }
            .sheet(isPresented: $viewModel.isPresentingProfile) {
                UserProfileView()
                    .environment(\.clerkTheme, .iris)
            }
            .onAppear { viewModel.loadProjects() }
        }
    }

    private var heroBanner: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp5)) {
            homeHeroHeaderRow
            heroCallToActionCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var homeHeroHeaderRow: some View {
        HStack(alignment: .center, spacing: .spacing(.sp3)) {
            Image("Iris_Outline")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(Color.ds.accentBg)
                .frame(width: 36, height: 36)

            HStack(alignment: .center, spacing: .spacing(.sp2)) {
                Text("Iris")
                .typography(.title)
                .foregroundStyle(Color.ds.text)

                Text("by Magnolia Creative")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
                    .padding(.top, 22)
            }
            

            Spacer(minLength: 0)

            profileButton
        }
    }

    private var heroCallToActionCard: some View {
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

            Button {
                viewModel.presentComponentShowcase()
            } label: {
                HStack(spacing: .spacing(.sp2)) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 14, weight: .semibold))

                    Text("Component Library")
                        .typography(.action)
                }
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(.horizontal, .sp4)
                .padding(.vertical, .sp3)
                .background(Color.white.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
            }
            .buttonStyle(.plain)
        }
        .padding(.sp6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
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
        }
        .overlay {
            RoundedRectangle(cornerRadius: .spacing(.sp5))
                .stroke(Color.ds.accentFg.opacity(0.38), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp5)))
    }

    private var profileButton: some View {
        Button {
            viewModel.presentProfile()
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.ds.text)
                .frame(width: 40, height: 40)
                .background(Color.ds.surface)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(Color.ds.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
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
                VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                    if let deleteError = viewModel.deleteProjectErrorMessage {
                        Text(deleteError)
                            .typography(.bodySmall)
                            .foregroundStyle(Color.red.opacity(0.9))
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.allProjects.enumerated()), id: \.element.projectId) { index, project in
                            SwipeToDeleteProjectRow {
                                viewModel.deleteProject(project)
                            } content: {
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
                            }

                            if index < viewModel.allProjects.count - 1 {
                                Divider()
                                    .padding(.leading, 128)
                            }
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

    private func projectDetailText(for project: Project) -> String {
        "\(project.resolutionLabel) • \(project.frameRate) fps • \(lastOpenedText(for: project))"
    }

    private func lastOpenedText(for project: Project) -> String {
        "Opened \(project.primaryTimestamp.formatted(.relative(presentation: .named)))"
    }

    @ViewBuilder
    private func editorDestination(for project: Project) -> some View {
        if let timeline = try? DatabaseManager.shared.getTimeline(forProjectId: project.projectId) {
            EditorContainerView(
                timelineId: timeline.timelineId,
                onReturnHome: viewModel.returnHomeFromEditor
            )
        } else {
            Text("No timeline found")
                .foregroundColor(Color.ds.textMuted)
        }
    }
}

private struct SwipeToDeleteProjectRow<Content: View>: View {
    private let revealWidth: CGFloat = 72
    let onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var lastCommittedOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button {
                    onDelete()
                    withAnimation(.easeOut(duration: 0.2)) {
                        offset = 0
                        lastCommittedOffset = 0
                    }
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: revealWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete project")
            }

            content()
                .background(Color.ds.bg)
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let combined = lastCommittedOffset + value.translation.width
                            offset = min(0, max(-revealWidth, combined))
                        }
                        .onEnded { value in
                            let combined = lastCommittedOffset + value.translation.width
                            let target: CGFloat = combined < -revealWidth / 2 ? -revealWidth : 0
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                                offset = target
                                lastCommittedOffset = target
                            }
                        }
                )
        }
        .clipped()
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
