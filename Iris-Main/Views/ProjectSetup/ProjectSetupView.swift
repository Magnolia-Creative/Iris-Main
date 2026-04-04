import SwiftUI
import PhotosUI

struct ProjectSetupView: View {
    @State private var projectName = ""
    @State private var selectedResolution: ResolutionOption = .hd1080
    @State private var selectedFrameRate: FrameRateOption = .fps30
    @State private var navigateToEditor = false
    @State private var navigateToAgent = false
    @State private var createdTimelineId: String?
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @Environment(\.dismiss) private var dismiss

    enum ResolutionOption: String, CaseIterable, Identifiable {
        case hd1080 = "1080p"
        case uhd4k = "4K"
        var id: String { rawValue }
        var width: Int { self == .hd1080 ? 1920 : 3840 }
        var height: Int { self == .hd1080 ? 1080 : 2160 }
    }

    enum FrameRateOption: Int, CaseIterable, Identifiable {
        case fps24 = 24
        case fps30 = 30
        case fps60 = 60
        var id: Int { rawValue }
        var label: String { "\(rawValue) fps" }
    }

    var body: some View {
        ZStack {
            Color.ds.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: .spacing(.sp6)) {
                    settingsSection
                    pathSection
                }
                .padding(.horizontal, .sp6)
                .padding(.vertical, .sp8)
            }
        }
        .navigationTitle("New Project")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToEditor) {
            if let id = createdTimelineId {
                EditorContainerView(timelineId: id)
            }
        }
        .navigationDestination(isPresented: $navigateToAgent) {
            if let id = createdTimelineId {
                ImportView()
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp4)) {
            Text("Project Settings")
                .typography(.heading)
                .foregroundColor(Color.ds.text)

            VStack(alignment: .leading, spacing: .spacing(.sp3)) {
                Text("Name").typography(.bodySmall).foregroundColor(Color.ds.textMuted)
                TextField("My Project", text: $projectName)
                    .typographyStyle(.body)
                    .padding(.sp3)
                    .background(Color.ds.surface)
                    .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
                    .overlay(RoundedRectangle(cornerRadius: .spacing(.sp2)).stroke(Color.ds.border, lineWidth: 1))
            }

            HStack(spacing: .spacing(.sp4)) {
                VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                    Text("Resolution").typography(.bodySmall).foregroundColor(Color.ds.textMuted)
                    Picker("Resolution", selection: $selectedResolution) {
                        ForEach(ResolutionOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                    Text("Frame Rate").typography(.bodySmall).foregroundColor(Color.ds.textMuted)
                    Picker("Frame Rate", selection: $selectedFrameRate) {
                        ForEach(FrameRateOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .padding(.sp6)
        .background(Color.ds.surface)
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4)))
        .overlay(RoundedRectangle(cornerRadius: .spacing(.sp4)).stroke(Color.ds.border, lineWidth: 1))
    }

    private var pathSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp4)) {
            Text("Get Started")
                .typography(.heading)
                .foregroundColor(Color.ds.text)

            Button { createProjectAndImport() } label: {
                HStack(spacing: .spacing(.sp3)) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: .spacing(.sp1)) {
                        Text("Import & Edit").typography(.body).foregroundColor(Color.ds.text)
                        Text("Add your clips and jump straight into editing")
                            .typography(.bodySmall).foregroundColor(Color.ds.textMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(Color.ds.textMuted)
                }
                .padding(.sp4)
                .background(Color.ds.surface)
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                .overlay(RoundedRectangle(cornerRadius: .spacing(.sp3)).stroke(Color.ds.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button { createProjectAndStartAgent() } label: {
                HStack(spacing: .spacing(.sp3)) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20))
                        .foregroundColor(Color.ds.accentFg)
                    VStack(alignment: .leading, spacing: .spacing(.sp1)) {
                        Text("AI Assembly").typography(.body).foregroundColor(Color.ds.text)
                        Text("Let the AI agent assemble your timeline from clips")
                            .typography(.bodySmall).foregroundColor(Color.ds.textMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(Color.ds.textMuted)
                }
                .padding(.sp4)
                .background(Color.ds.surface)
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                .overlay(RoundedRectangle(cornerRadius: .spacing(.sp3)).stroke(Color.ds.accentFg.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func createProjectAndImport() {
        guard let timelineId = createProject() else { return }
        createdTimelineId = timelineId
        navigateToEditor = true
    }

    private func createProjectAndStartAgent() {
        guard let timelineId = createProject() else { return }
        createdTimelineId = timelineId
        navigateToAgent = true
    }

    private func createProject() -> String? {
        let name = projectName.isEmpty ? "Untitled" : projectName
        let project = Project(
            name: name,
            resolutionWidth: selectedResolution.width,
            resolutionHeight: selectedResolution.height,
            frameRate: selectedFrameRate.rawValue
        )

        do {
            try DatabaseManager.shared.create(project)
            let library = MediaLibrary(projectId: project.projectId)
            try DatabaseManager.shared.create(library)
            let timeline = try DatabaseManager.shared.createTimeline(forProjectId: project.projectId)
            return timeline.timelineId
        } catch {
            print("Failed to create project: \(error)")
            return nil
        }
    }
}
