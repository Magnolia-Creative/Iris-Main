import SwiftUI

struct EditorBottomChromeStack<Dock: View>: View {
    let plan: EditorBottomChromePlan
    @Binding var activeParameterGroupId: String
    @Binding var parameterValues: [String: EditorParameterValue]
    var onAction: (EditorChromeActionItem) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    var onScalarChange: ((String, Double) -> Void)?
    let dock: () -> Dock

    @State private var subchromeHeight: CGFloat = 0
    @State private var navigationSize: CGSize = .zero

    init(
        plan: EditorBottomChromePlan,
        activeParameterGroupId: Binding<String>,
        parameterValues: Binding<[String: EditorParameterValue]>,
        onAction: @escaping (EditorChromeActionItem) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {},
        onScalarChange: ((String, Double) -> Void)? = nil,
        @ViewBuilder dock: @escaping () -> Dock
    ) {
        self.plan = plan
        self._activeParameterGroupId = activeParameterGroupId
        self._parameterValues = parameterValues
        self.onAction = onAction
        self.onDismiss = onDismiss
        self.onScalarChange = onScalarChange
        self.dock = dock
    }

    private var showsSubchrome: Bool {
        !plan.spatialParameters.isEmpty
            || !plan.parameterGroups.isEmpty
            || !plan.actions.isEmpty
            || plan.isDismissable
    }

    private var stackSpacing: CGFloat {
        showsSubchrome && plan.showsDock ? .spacing(.sp2) : plan.density.tierVerticalSpacing
    }

    private var navigationCutoutSize: CGSize {
        CGSize(
            width: navigationSize.width + .spacing(.sp3),
            height: navigationSize.height + .spacing(.sp2)
        )
    }

    private var navigationCutoutOffsetY: CGFloat {
        subchromeHeight + .spacing(.sp2) - .spacing(.sp1)
    }

    var body: some View {
        VStack(spacing: stackSpacing) {
            if showsSubchrome {
                subchromeContent
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: EditorBottomChromeSubchromeHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if plan.showsDock {
                dock()
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: EditorBottomChromeNavigationSizeKey.self,
                                value: proxy.size
                            )
                        }
                    }
            }
        }
        .padding(.bottom, showsSubchrome ? .spacing(.sp2) : 0)
        .background {
            if showsSubchrome {
                EditorChromeSurfaceComponent {
                    Color.clear
                }
                .mask {
                    ZStack(alignment: .top) {
                        Rectangle().fill(Color.white)

                        if plan.showsDock, navigationSize != .zero {
                            RoundedRectangle(
                                cornerRadius: navigationCutoutSize.height / 2,
                                style: .continuous
                            )
                            .fill(Color.white)
                            .frame(width: navigationCutoutSize.width, height: navigationCutoutSize.height)
                            .offset(y: navigationCutoutOffsetY)
                            .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showsSubchrome)
        .onPreferenceChange(EditorBottomChromeSubchromeHeightKey.self) { subchromeHeight = $0 }
        .onPreferenceChange(EditorBottomChromeNavigationSizeKey.self) { navigationSize = $0 }
    }

    private var subchromeContent: some View {
        VStack(alignment: .leading, spacing: plan.density.tierVerticalSpacing) {
            if !plan.spatialParameters.isEmpty {
                EditorSpatialParameterTierView(
                    descriptors: plan.spatialParameters,
                    density: plan.density
                )
            }

            if !plan.parameterGroups.isEmpty {
                EditorParameterTierView(
                    groups: plan.parameterGroups,
                    density: plan.density,
                    showsOverflowChips: plan.showsOverflowChips,
                    activeGroupId: $activeParameterGroupId,
                    values: $parameterValues,
                    onScalarChange: onScalarChange
                )
            }

            if plan.isDismissable || !plan.actions.isEmpty {
                EditorImmediateActionsRow(
                    actions: plan.actions,
                    isDismissable: plan.isDismissable,
                    onDismiss: onDismiss,
                    onAction: onAction
                )
            }
        }
        .padding(.horizontal, .spacing(.sp3))
        .padding(.top, .spacing(.sp3))
        .padding(.bottom, .spacing(.sp3))
    }
}

private struct EditorBottomChromeSubchromeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct EditorBottomChromeNavigationSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
