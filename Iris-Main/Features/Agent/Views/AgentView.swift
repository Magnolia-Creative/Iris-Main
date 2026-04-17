import SwiftUI

struct AgentView: View {
    @ObservedObject var viewModel: AgentViewModel
    let transitionNamespace: Namespace.ID
    let secondaryContentOpacity: Double
    var promptIsSource = true
    private let gridColumns = Array(
        repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: .spacing(.sp2)),
        count: 3
    )

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp6)) {
            importedClipsSection
            promptSection

            ScrollView(showsIndicators: false) {
                secondaryContent
                    .padding(.bottom, .sp6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarBackButtonHidden(true)
        .padding(.horizontal, .sp4)
        .padding(.top, .sp2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await viewModel.startIfNeeded()
        }
    }

    private var secondaryContent: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp6)) {
            AgentStatusSectionView(
                statusMessage: viewModel.model.statusMessage,
                isAnimating: viewModel.model.showsAnimatedStatusSweep,
                reasoningNotes: viewModel.model.reasoningNotes,
                errorMessage: viewModel.model.errorMessage
            )
            AgentExtractionSectionView(clips: viewModel.model.extractionClips)
            if showsTimelineSection {
                AgentTimelineSectionView(clips: viewModel.model.timelineClips)
            }
        }
        .opacity(secondaryContentOpacity)
        .offset(y: CGFloat(1 - secondaryContentOpacity) * 18)
        .animation(.easeOut(duration: 0.24), value: secondaryContentOpacity)
    }

    private var promptSection: some View {
        ImportPromptDisplayCard(text: viewModel.model.promptText)
            .importPromptCardTransition(in: transitionNamespace, isSource: promptIsSource)
    }

    @ViewBuilder
    private var importedClipsSection: some View {
        if !viewModel.model.importedClips.isEmpty {
            VStack(alignment: .leading, spacing: .spacing(.sp3)) {
                Text("Imported clips")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)

                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: .spacing(.sp2)) {
                    ForEach(viewModel.model.importedClips) { clip in
                        ImportedVideoTile(videoURL: clip.videoURL)
                            .importVideoTileTransition(id: clip.id, in: transitionNamespace, isSource: false)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
            }
            .importVideosSectionTransition(in: transitionNamespace, isSource: false)
        }
    }
    
    private var showsTimelineSection: Bool {
        !viewModel.model.timelineClips.isEmpty
            || viewModel.model.stage == .assemblingTimeline
            || viewModel.model.canLaunchEditorReview
    }
}
