import SwiftUI

/// Top chrome pill that sits above the pinned `EditorBottomNavBar`. Houses the
/// prompt bar, clip tools (when a clip is selected in Edit), or the
/// space-specific extension content for Import/Export. This view is free to
/// resize horizontally — the bottom nav row lives in a separate sibling view
/// so it is never affected by changes here.
struct EditorTabBar<PromptBar: View, SpaceExtension: View>: View {
    @Binding var activeSpace: EditorSpace
    let isClipSelected: Bool
    let promptBarIsTakingOver: Bool
    let selectedClipColorFilter: ClipColorFilter
    let onSplitClip: () -> Void
    let onDeleteClip: () -> Void
    let onSetClipColorFilter: (ClipColorFilter) -> Void
    let onResetClipColorFilter: () -> Void
    let selectedClipVolume: ClipVolume
    let onSetClipVolume: (ClipVolume) -> Void
    let onResetClipVolume: () -> Void
    let onDeselectClip: () -> Void
    /// When true, `promptActionReviewReplacement` is shown instead of the normal prompt bar.
    let isPromptActionReviewActive: Bool
    /// When set, replaces the prompt bar (mic / typing / chat) with this content while keeping the tab bar shell.
    let promptActionReviewReplacement: AnyView?
    /// Drives cross-fade when switching between sequence review, color review substeps, and other leading content.
    let promptReviewReplacementSlotIdentity: String
    /// Extra space reserved inside the glass shell at the bottom so the pinned
    /// nav bar can overlap the chrome in z without changing its layout.
    let bottomReservedSpace: CGFloat
    /// Maximum width for the top chrome glass shell. When `nil`, the chrome
    /// fills the proposed width as before. When set, the chrome is capped at
    /// this width (unless `hugChromeToContent` is true — clip tools always
    /// hug their intrinsic content width).
    let chromeMaxWidth: CGFloat?
    let promptBar: (Bool, Namespace.ID) -> PromptBar
    let spaceExtension: SpaceExtension
    /// When set and `activeSpace == .edit`, replaces the edit tools row (same chrome as import/export).
    let captionsEditContent: AnyView?
    /// True while the captions style chrome is mounted (drives entry/exit transition + width gating).
    let isCaptionsChromeActive: Bool
    /// True while a caption style tool (style, background, …) is expanded inline.
    /// Causes the chrome to drop its width cap so the expanded options have room.
    let isCaptionsToolExpanded: Bool

    @Environment(\.colorScheme) private var colorScheme

    @Namespace private var promptNamespace
    @State private var expandedToolId: Int = -1

    private let outerCornerRadius: CGFloat = 24

    init(
        activeSpace: Binding<EditorSpace>,
        isClipSelected: Bool,
        promptBarIsTakingOver: Bool,
        selectedClipColorFilter: ClipColorFilter = .neutral,
        onSplitClip: @escaping () -> Void,
        onDeleteClip: @escaping () -> Void,
        onSetClipColorFilter: @escaping (ClipColorFilter) -> Void = { _ in },
        onResetClipColorFilter: @escaping () -> Void = {},
        selectedClipVolume: ClipVolume = .neutral,
        onSetClipVolume: @escaping (ClipVolume) -> Void = { _ in },
        onResetClipVolume: @escaping () -> Void = {},
        onDeselectClip: @escaping () -> Void = {},
        isPromptActionReviewActive: Bool = false,
        promptActionReviewReplacement: AnyView? = nil,
        promptReviewReplacementSlotIdentity: String = "",
        bottomReservedSpace: CGFloat = 0,
        chromeMaxWidth: CGFloat? = nil,
        @ViewBuilder promptBar: @escaping (Bool, Namespace.ID) -> PromptBar,
        captionsEditContent: AnyView? = nil,
        isCaptionsChromeActive: Bool = false,
        isCaptionsToolExpanded: Bool = false,
        @ViewBuilder spaceExtension: () -> SpaceExtension
    ) {
        self._activeSpace = activeSpace
        self.isClipSelected = isClipSelected
        self.promptBarIsTakingOver = promptBarIsTakingOver
        self.selectedClipColorFilter = selectedClipColorFilter
        self.onSplitClip = onSplitClip
        self.onDeleteClip = onDeleteClip
        self.onSetClipColorFilter = onSetClipColorFilter
        self.onResetClipColorFilter = onResetClipColorFilter
        self.selectedClipVolume = selectedClipVolume
        self.onSetClipVolume = onSetClipVolume
        self.onResetClipVolume = onResetClipVolume
        self.onDeselectClip = onDeselectClip
        self.isPromptActionReviewActive = isPromptActionReviewActive
        self.promptActionReviewReplacement = promptActionReviewReplacement
        self.promptReviewReplacementSlotIdentity = promptReviewReplacementSlotIdentity
        self.bottomReservedSpace = bottomReservedSpace
        self.chromeMaxWidth = chromeMaxWidth
        self.promptBar = promptBar
        self.spaceExtension = spaceExtension()
        self.captionsEditContent = captionsEditContent
        self.isCaptionsChromeActive = isCaptionsChromeActive
        self.isCaptionsToolExpanded = isCaptionsToolExpanded
    }

    private var rowMaxWidth: CGFloat? {
        // When a clip is selected and the prompt bar is in its compact idle
        // layout, or when prompt-action review replaces the prompt slot, let the
        // entire row size to content so the glass pill hugs tightly. Otherwise
        // expand so the prompt bar can center properly.
        if isPromptActionReviewActive {
            return nil
        }
        if isClipSelected && !promptBarIsTakingOver {
            return nil
        }
        return .infinity
    }

    /// Clip idle or prompt-action review: shell sizes to content; caption style
    /// chrome uses full width and fixed vertical footprint (see `topChrome`).
    private var hugChromeToContent: Bool {
        activeSpace == .edit
            && !isClipToolSliderExpanded
            && !isCaptionsToolExpanded
            && (
                isPromptActionReviewActive
                    || (isClipSelected && !promptBarIsTakingOver)
            )
    }

    private var isClipToolSliderExpanded: Bool {
        ClipToolsChromeView.isSliderExpandedTool(id: expandedToolId)
    }

    var body: some View {
        topChrome
            .modifier(ChromeMaxWidthModifier(
                maxWidth: (hugChromeToContent || isClipToolSliderExpanded || isCaptionsToolExpanded) ? nil : chromeMaxWidth
            ))
            .editorRegularGlassEffect(
                tint: shellTint,
                in: RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
            )
            .shadow(color: outerShadowColor, radius: 20, x: 0, y: 14)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: activeSpace)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isCaptionsChromeActive)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isCaptionsToolExpanded)
            .onChange(of: isClipSelected) { _, _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { expandedToolId = -1 }
            }
            .onChange(of: activeSpace) { _, _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { expandedToolId = -1 }
            }
            .onChange(of: promptBarIsTakingOver) { _, isTakingOver in
                guard isTakingOver else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { expandedToolId = -1 }
            }
            .onChange(of: isPromptActionReviewActive) { _, active in
                guard active else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { expandedToolId = -1 }
            }
    }

    private var topChrome: some View {
        ZStack {
            if activeSpace == .edit, let captionsEditContent {
                captionsEditContent
                    .frame(minHeight: .spacing(.sp8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .center)),
                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .center))
                        )
                    )
            } else if activeSpace == .edit {
                toolsRow
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .center)),
                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .center))
                        )
                    )
            } else {
                spaceExtension
            }
        }
        .padding(.horizontal, .spacing(.sp3))
        .padding(.top, .spacing(.sp3))
        .padding(.bottom, .spacing(.sp3) + bottomReservedSpace)
        .modifier(HorizontalHugWhenEnabled(enabled: hugChromeToContent))
    }

    // MARK: - Outer Shell

    private var shellTint: Color {
        Color.white.opacity(colorScheme == .dark ? 0.02 : 0.08)
    }

    private var outerShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.55)
            : Color.black.opacity(0.12)
    }

    // MARK: - Edit Tools Row

    @ViewBuilder
    private var toolsRow: some View {
        let clipIdle = isClipSelected && !promptBarIsTakingOver && !isPromptActionReviewActive
        let leadingCompact = clipIdle || isPromptActionReviewActive
        HStack(spacing: .spacing(.sp2)) {
            if clipIdle {
                ClipToolsChromeView(
                    expandedToolId: $expandedToolId,
                    selectedClipColorFilter: selectedClipColorFilter,
                    selectedClipVolume: selectedClipVolume,
                    onSplitClip: onSplitClip,
                    onDeleteClip: onDeleteClip,
                    onSetClipColorFilter: onSetClipColorFilter,
                    onResetClipColorFilter: onResetClipColorFilter,
                    onSetClipVolume: onSetClipVolume,
                    onResetClipVolume: onResetClipVolume,
                    onDeselectClip: onDeselectClip
                )
            } else {
                ZStack(alignment: .leading) {
                    if let promptActionReviewReplacement {
                        promptActionReviewReplacement
                            .fixedSize(horizontal: true, vertical: false)
                            .transition(
                                .opacity.combined(with: .scale(scale: 0.98, anchor: .leading))
                            )
                    } else {
                        promptBar(isClipSelected, promptNamespace)
                            .transition(
                                .opacity.combined(with: .scale(scale: 0.98, anchor: .leading))
                            )
                    }
                }
                .contentTransition(.opacity)
                .layoutPriority(leadingCompact ? 0 : 1)
            }
        }
        .frame(maxWidth: rowMaxWidth)
        .frame(minHeight: .spacing(.sp8))
        .frame(
            maxWidth: leadingCompact ? nil : .infinity,
            alignment: leadingCompact ? .leading : .center
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: expandedToolId)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isClipSelected)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: promptBarIsTakingOver)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPromptActionReviewActive)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: promptReviewReplacementSlotIdentity)
    }
}

/// Lets the top chrome shrink to intrinsic width when clip tools are shown.
private struct HorizontalHugWhenEnabled: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.fixedSize(horizontal: true, vertical: false)
        } else {
            content
        }
    }
}

/// Caps the chrome to a maximum width when provided; passes through otherwise.
private struct ChromeMaxWidthModifier: ViewModifier {
    let maxWidth: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let maxWidth {
            content.frame(maxWidth: maxWidth, alignment: .center)
        } else {
            content
        }
    }
}

