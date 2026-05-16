import SwiftUI

struct ProjectSetupView: View {
    let onReturnHome: (() -> Void)?
    @State private var screen: Screen = .chooser
    @State private var navigateToEditor = false
    @State private var createdTimelineId: String?
    @State private var introTitle: String

    enum Screen {
        case chooser
        case automake
    }

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

    init(onReturnHome: (() -> Void)? = nil) {
        self.onReturnHome = onReturnHome
        _introTitle = State(initialValue: Self.introPhrases.randomElement() ?? "Begin your Magnum Opus")
    }

    var body: some View {
        ZStack {
            switch screen {
            case .chooser:
                Color.ds.bg
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: .spacing(.sp5)) {
                        heroSection
                            .padding(.horizontal, .sp4)
                            .padding(.top, .sp3)
                        chooserContent
                    }
                    .padding(.bottom, .sp8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            case .automake:
                Color.ds.bg
                    .ignoresSafeArea()

                automakeContent
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToEditor) {
            if let id = createdTimelineId {
                EditorContainerView(timelineId: id, onReturnHome: onReturnHome)
            }
        }
        .toolbar {
            if screen == .automake {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            screen = .chooser
                        }
                    }
                    .foregroundStyle(Color.ds.text)
                }
            }
        }
    }

    private var chooserContent: some View {
        pathSection
            .padding(.horizontal, .sp4)
            .padding(.top, .sp5)
    }

    private var automakeContent: some View {
        Group {
            if let timelineId = createdTimelineId {
                ImportView(timelineId: timelineId, onReturnHome: onReturnHome)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .frame(height: 24)

            Text(introTitle)
                .typography(.title)
                .foregroundStyle(Color.ds.text)

            Text("Set up your timeline, then choose whether you want to jump straight into editing or let AutoMake assemble the first pass.")
                .typography(.body)
                .foregroundStyle(Color.ds.textMuted)
                .frame(maxWidth: 340, alignment: .leading)
        }
    }

    private var pathSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp4)) {
            Text("Choose your path")
                .typography(.heading)
                .foregroundColor(Color.ds.text)

            Text("Import clips manually and cut right away, or move into AutoMake to build a first draft from your footage and prompt.")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            Button { createProjectAndImport() } label: {
                SetupPathCard(
                    iconName: "play.rectangle.on.rectangle",
                    iconColor: Color.ds.text,
                    title: "Import & Edit",
                    subtitle: "Create the project and go straight into the editor.",
                    borderColor: Color.ds.border
                )
            }
            .buttonStyle(.plain)

            Button { enterAutoMake() } label: {
                SetupPathCard(
                    iconName: "sparkles",
                    iconColor: Color.ds.accentFg,
                    title: "AutoMake",
                    subtitle: "Switch into the AI assembly flow with video import and prompt setup.",
                    borderColor: Color.ds.accentFg.opacity(0.35)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func createProjectAndImport() {
        guard let timelineId = createProject() else { return }
        createdTimelineId = timelineId
        navigateToEditor = true
    }

    private func enterAutoMake() {
        if createdTimelineId == nil {
            createdTimelineId = createProject()
        }

        guard createdTimelineId != nil else { return }

        withAnimation(.easeInOut(duration: 0.22)) {
            screen = .automake
        }
    }

    private func createProject() -> String? {
        let project = Project(
            name: Self.projectDateFormatter.string(from: Date()),
            resolutionWidth: ResolutionOption.hd1080.width,
            resolutionHeight: ResolutionOption.hd1080.height,
            frameRate: FrameRateOption.fps30.rawValue
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

    private static let introPhrases = [
        "Begin your Magnum Opus",
        "The Start of a Spectacle",
        "Cue the Main Event",
        "Roll the Opening Scene",
        "Compose Your Next Masterpiece"
    ]

    private static let projectDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct SetupPathCard: View {
    let iconName: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let borderColor: Color

    var body: some View {
        HStack(alignment: .center, spacing: .spacing(.sp3)) {
            ZStack {
                RoundedRectangle(cornerRadius: .spacing(.sp3))
                    .fill(Color.ds.bg.opacity(0.9))
                    .frame(width: 48, height: 48)

                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: .spacing(.sp1)) {
                Text(title)
                    .typography(.body)
                    .foregroundColor(Color.ds.text)

                Text(subtitle)
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: .spacing(.sp3))

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.ds.textMuted)
        }
        .padding(.sp4)
        .background(Color.ds.surface)
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4)))
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp4))
                .stroke(borderColor, lineWidth: 1)
        )
    }
}
