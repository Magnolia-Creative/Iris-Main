import SwiftUI

struct EditorImportRequest: Identifiable {
    enum Destination: Equatable {
        case library
        case timeline(kind: TrackKind)

        var applicationMode: EditorImportApplicationMode {
            switch self {
            case .library:
                return .libraryOnly
            case .timeline(let kind):
                return .timeline(kind: kind)
            }
        }
    }

    let id = UUID()
    let destination: Destination
}

enum EditorImportApplicationMode: Equatable {
    case libraryOnly
    case timeline(kind: TrackKind)
}

struct EditorClipImportSheet: View {
    let timelineId: String
    let onAdd: @MainActor ([Media]) -> Void
    @StateObject private var viewModel: ImportBrowserViewModel

    init(timelineId: String, onAdd: @escaping @MainActor ([Media]) -> Void) {
        self.timelineId = timelineId
        self.onAdd = onAdd
        _viewModel = StateObject(wrappedValue: ImportBrowserViewModel(timelineId: timelineId))
    }

    var body: some View {
        ClipImportSheetView(
            viewModel: viewModel,
            onAdd: {
                let media = await viewModel.finalizeSelectedMediaImports()
                await MainActor.run {
                    onAdd(media)
                }
            }
        )
        .task {
            viewModel.updateProcessingMode(.embeddingsAndAgentPreprocessing)
        }
    }
}
