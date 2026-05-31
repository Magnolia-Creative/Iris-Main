import Foundation

enum UIWidgetRole: String, Codable, Equatable {
    case monitor
    case representation
    case inspector
    case tool
    case navigator
    case review
}

enum UIControlType: String, Codable, Equatable {
    case slider
    case toggle
    case segmented
    case button
    case textField
}

enum UIProminence: String, Codable, Equatable {
    case primary
    case supporting
    case compact
    case hidden
}

enum UILayoutNodeType: String, Codable, Equatable {
    case vstack
    case hstack
    case zstack
    case widget
    case toolbar
}

struct UIWidgetSizeHint: Codable, Equatable {
    let weight: Double?
    let minHeight: Double?
    let maxHeight: Double?
    let importance: UIProminence?
    let collapsible: Bool?
}

struct UIParameterControl: Codable, Equatable, Identifiable {
    var id: String { parameterId }
    let parameterId: String
    let control: UIControlType
    let label: String?
    let minValue: Double?
    let maxValue: Double?
    let defaultValue: Double?
}

struct UIWidgetPlacement: Codable, Equatable, Identifiable {
    var id: String { "\(widgetId)-\(intentSliceId)-\(variant ?? "default")" }
    let widgetId: String
    let variant: String?
    let prominence: UIProminence
    let size: UIWidgetSizeHint?
    let intentSliceId: String
    let reason: String?
    let controls: [UIParameterControl]
    let props: [String: String]?

    init(
        widgetId: String,
        variant: String? = nil,
        prominence: UIProminence = .supporting,
        size: UIWidgetSizeHint? = nil,
        intentSliceId: String,
        reason: String? = nil,
        controls: [UIParameterControl] = [],
        props: [String: String]? = nil
    ) {
        self.widgetId = widgetId
        self.variant = variant
        self.prominence = prominence
        self.size = size
        self.intentSliceId = intentSliceId
        self.reason = reason
        self.controls = controls
        self.props = props
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        widgetId = try container.decode(String.self, forKey: .widgetId)
        variant = try container.decodeIfPresent(String.self, forKey: .variant)
        prominence = try container.decodeIfPresent(UIProminence.self, forKey: .prominence) ?? .supporting
        size = try container.decodeIfPresent(UIWidgetSizeHint.self, forKey: .size)
        intentSliceId = try container.decode(String.self, forKey: .intentSliceId)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        controls = try container.decodeIfPresent([UIParameterControl].self, forKey: .controls) ?? []
        props = try container.decodeIfPresent([String: String].self, forKey: .props)
    }
}

struct UILayoutNode: Codable, Equatable {
    let type: UILayoutNodeType
    let children: [UILayoutNode]
    let widget: UIWidgetPlacement?
    let size: UIWidgetSizeHint?

    init(
        type: UILayoutNodeType,
        children: [UILayoutNode] = [],
        widget: UIWidgetPlacement? = nil,
        size: UIWidgetSizeHint? = nil
    ) {
        self.type = type
        self.children = children
        self.widget = widget
        self.size = size
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(UILayoutNodeType.self, forKey: .type)
        children = try container.decodeIfPresent([UILayoutNode].self, forKey: .children) ?? []
        widget = try container.decodeIfPresent(UIWidgetPlacement.self, forKey: .widget)
        size = try container.decodeIfPresent(UIWidgetSizeHint.self, forKey: .size)
    }
}

struct UIIntentSlice: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let goal: String
    let modality: String
    let parameterIds: [String]

    init(
        id: String,
        title: String,
        goal: String,
        modality: String = "mixed",
        parameterIds: [String] = []
    ) {
        self.id = id
        self.title = title
        self.goal = goal
        self.modality = modality
        self.parameterIds = parameterIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        goal = try container.decode(String.self, forKey: .goal)
        modality = try container.decodeIfPresent(String.self, forKey: .modality) ?? "mixed"
        parameterIds = try container.decodeIfPresent([String].self, forKey: .parameterIds) ?? []
    }
}

struct UIToolbarPlacement: Codable, Equatable {
    let widgets: [UIWidgetPlacement]
    let showNavigation: Bool
    let showPromptBar: Bool

    init(
        widgets: [UIWidgetPlacement] = [],
        showNavigation: Bool = false,
        showPromptBar: Bool = false
    ) {
        self.widgets = widgets
        self.showNavigation = showNavigation
        self.showPromptBar = showPromptBar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        widgets = try container.decodeIfPresent([UIWidgetPlacement].self, forKey: .widgets) ?? []
        showNavigation = try container.decodeIfPresent(Bool.self, forKey: .showNavigation) ?? false
        showPromptBar = try container.decodeIfPresent(Bool.self, forKey: .showPromptBar) ?? false
    }
}

struct UIWorkspacePlan: Codable, Equatable {
    let catalogVersion: String
    let workspaceId: String
    let intentSummary: String
    let intentSlices: [UIIntentSlice]
    let currentSliceId: String?
    let currentSliceIndex: Int
    let layout: UILayoutNode
    let toolbar: UIToolbarPlacement
    let hiddenBecauseIrrelevant: [String]
    let warnings: [String]
    let isDefaultWorkspace: Bool
    let restoreDefaultOnComplete: Bool

    init(
        catalogVersion: String = UIWorkspaceCatalog.version,
        workspaceId: String,
        intentSummary: String,
        intentSlices: [UIIntentSlice],
        currentSliceId: String?,
        currentSliceIndex: Int,
        layout: UILayoutNode,
        toolbar: UIToolbarPlacement,
        hiddenBecauseIrrelevant: [String] = [],
        warnings: [String] = [],
        isDefaultWorkspace: Bool = false,
        restoreDefaultOnComplete: Bool = true
    ) {
        self.catalogVersion = catalogVersion
        self.workspaceId = workspaceId
        self.intentSummary = intentSummary
        self.intentSlices = intentSlices
        self.currentSliceId = currentSliceId
        self.currentSliceIndex = currentSliceIndex
        self.layout = layout
        self.toolbar = toolbar
        self.hiddenBecauseIrrelevant = hiddenBecauseIrrelevant
        self.warnings = warnings
        self.isDefaultWorkspace = isDefaultWorkspace
        self.restoreDefaultOnComplete = restoreDefaultOnComplete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        catalogVersion = try container.decodeIfPresent(String.self, forKey: .catalogVersion) ?? "1"
        workspaceId = try container.decode(String.self, forKey: .workspaceId)
        intentSummary = try container.decode(String.self, forKey: .intentSummary)
        intentSlices = try container.decodeIfPresent([UIIntentSlice].self, forKey: .intentSlices) ?? []
        currentSliceId = try container.decodeIfPresent(String.self, forKey: .currentSliceId)
        currentSliceIndex = try container.decodeIfPresent(Int.self, forKey: .currentSliceIndex) ?? 0
        layout = try container.decode(UILayoutNode.self, forKey: .layout)
        toolbar = try container.decode(UIToolbarPlacement.self, forKey: .toolbar)
        hiddenBecauseIrrelevant = try container.decodeIfPresent([String].self, forKey: .hiddenBecauseIrrelevant) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        isDefaultWorkspace = try container.decodeIfPresent(Bool.self, forKey: .isDefaultWorkspace) ?? false
        restoreDefaultOnComplete = try container.decodeIfPresent(Bool.self, forKey: .restoreDefaultOnComplete) ?? true
    }
}

struct UIEditorContext: Codable, Equatable {
    let activeSpace: String?
    let hasSelectedClip: Bool
    let hasSelectedCaption: Bool
    let hasVideoClips: Bool
    let hasAudioClips: Bool
    let isReviewActive: Bool
    let isPromptActionReviewActive: Bool
    let isCaptionsChromeActive: Bool
    let clientCatalogVersion: String?

    init(
        activeSpace: String? = nil,
        hasSelectedClip: Bool = false,
        hasSelectedCaption: Bool = false,
        hasVideoClips: Bool = false,
        hasAudioClips: Bool = false,
        isReviewActive: Bool = false,
        isPromptActionReviewActive: Bool = false,
        isCaptionsChromeActive: Bool = false,
        clientCatalogVersion: String? = UIWorkspaceCatalog.version
    ) {
        self.activeSpace = activeSpace
        self.hasSelectedClip = hasSelectedClip
        self.hasSelectedCaption = hasSelectedCaption
        self.hasVideoClips = hasVideoClips
        self.hasAudioClips = hasAudioClips
        self.isReviewActive = isReviewActive
        self.isPromptActionReviewActive = isPromptActionReviewActive
        self.isCaptionsChromeActive = isCaptionsChromeActive
        self.clientCatalogVersion = clientCatalogVersion
    }
}

struct UIWorkspacePlanRequest: Codable, Equatable {
    let prompt: String
    let context: IntentCompilerContext
    let editorContext: UIEditorContext?
    let intentResult: IntentCompileResult?
    let currentWorkspaceId: String?
}

struct UIWorkspacePlanResponse: Codable, Equatable {
    let plan: UIWorkspacePlan
}
