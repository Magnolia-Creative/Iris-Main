internal import Combine
import Foundation

@MainActor
final class EditorJITRecipeShowcaseViewModel: ObservableObject {
    @Published private(set) var renderState: EditorJITRenderState
    @Published private(set) var validationResult: EditorJITValidationResult
    @Published private(set) var transitionPlans: [EditorJITTransitionPlan] = []
    @Published var selectedRecipeId: String

    let recipes: [EditorJITRecipe]

    init(recipes: [EditorJITRecipe] = EditorJITRecipeCatalog.all) {
        self.recipes = recipes
        let defaultRecipe = EditorJITRecipeCatalog.defaultRecipe
        self.selectedRecipeId = defaultRecipe.id
        let (state, result) = EditorJITRenderValidator.validate(defaultRecipe.makeRawState())
        self.renderState = state
        self.validationResult = result
    }

    func selectRecipe(id: String) {
        guard selectedRecipeId != id else { return }
        guard let recipe = recipes.first(where: { $0.id == id }) else { return }

        let previous = renderState
        selectedRecipeId = id
        apply(recipe: recipe, previous: previous)
    }

    func revalidateCurrentRecipe() {
        guard let recipe = recipes.first(where: { $0.id == selectedRecipeId }) else { return }
        apply(recipe: recipe, previous: renderState)
    }

    private func apply(recipe: EditorJITRecipe, previous: EditorJITRenderState) {
        let (validated, result) = EditorJITRenderValidator.validate(recipe.makeRawState())
        transitionPlans = EditorJITRenderTransitionCoordinator.plan(from: previous, to: validated)
        renderState = validated
        validationResult = result
    }
}
