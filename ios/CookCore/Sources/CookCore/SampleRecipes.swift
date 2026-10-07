import Foundation

/// Authored examples are opt-in and remain visibly distinguishable from user imports.
public enum SampleRecipes {
    public static var recipes: [Recipe] {
        let created = Date(timeIntervalSince1970: 1_759_795_200)
        return [
            Recipe(
                id: UUID(uuidString: "C0010000-0000-4000-8000-000000000001")!,
                title: "Garlic Butter Shrimp Pasta",
                summary: "Garlic butter coats tender shrimp and pasta, finished with lemon and parsley.",
                servings: 2, prepMinutes: 5, cookMinutes: 15,
                ingredients: [
                    .from(name: "Pasta", amountText: "200 g", category: .pantry),
                    .from(name: "Peeled shrimp", amountText: "250 g", category: .proteins),
                    .from(name: "Butter", amountText: "30 g", category: .dairy),
                    .from(name: "Garlic", amountText: "2 cloves", category: .produce),
                    .from(name: "Lemon", amountText: "1", category: .produce),
                    .from(name: "Chopped parsley", amountText: "2 tbsp", category: .produce)
                ],
                steps: [
                    RecipeStep(title: "Prepare", instruction: "Pat the peeled shrimp dry. Mince the garlic, chop the parsley and cut the lemon into wedges."),
                    RecipeStep(title: "Cook pasta", instruction: "Boil the pasta in water for the time on its package. Start with 10 minutes, check for tenderness, and reserve a small cup of cooking water.", durationSeconds: 600),
                    RecipeStep(title: "Cook shrimp & toss", instruction: "Melt the butter in a wide pan over medium heat. Cook the shrimp on both sides until opaque and cooked through, then stir in the garlic until fragrant. Toss with the pasta, parsley and a squeeze of lemon. Add reserved cooking water a spoonful at a time to loosen.")
                ],
                sourceName: "Sample recipe", coverAsset: "pasta", createdAt: created, updatedAt: created
            ),
            Recipe(
                id: UUID(uuidString: "C0010000-0000-4000-8000-000000000002")!,
                title: "Avocado Salad",
                summary: "Creamy avocado, crisp cucumber and cherry tomatoes with a lemon dressing.",
                servings: 2, prepMinutes: 15, cookMinutes: 0,
                ingredients: [
                    .from(name: "Avocado", amountText: "1", category: .produce),
                    .from(name: "Cucumber", amountText: "1", category: .produce),
                    .from(name: "Cherry tomatoes", amountText: "200 g", category: .produce),
                    .from(name: "Mixed salad leaves", amountText: "50 g", category: .produce),
                    .from(name: "Olive oil", amountText: "2 tbsp", category: .pantry),
                    .from(name: "Lemon juice", amountText: "1 tbsp", category: .produce)
                ],
                steps: [
                    RecipeStep(title: "Chop", instruction: "Wash and dry the salad leaves. Slice the cucumber, halve the cherry tomatoes and cut the avocado into chunks."),
                    RecipeStep(title: "Dress", instruction: "Whisk the olive oil and lemon juice in a bowl. Add the leaves, cucumber and tomatoes, then toss gently."),
                    RecipeStep(title: "Finish", instruction: "Fold in the avocado without crushing it. Let the salad stand for 2 minutes, then divide between bowls and serve.", durationSeconds: 120)
                ],
                sourceName: "Sample recipe", coverAsset: "salad", createdAt: created, updatedAt: created
            ),
            Recipe(
                id: UUID(uuidString: "C0010000-0000-4000-8000-000000000003")!,
                title: "Weekend oat pancakes",
                summary: "Small oat pancakes for an easy breakfast.",
                category: .breakfast, servings: 2, prepMinutes: 10, cookMinutes: 15,
                ingredients: [
                    .from(name: "Oat flour", amountText: "100 g", category: .pantry),
                    .from(name: "Milk", amountText: "150 ml", category: .dairy),
                    .from(name: "Egg", amountText: "1", category: .dairy),
                    .from(name: "Baking powder", amountText: "1 tsp", category: .pantry),
                    .from(name: "Butter", amountText: "10 g", category: .dairy)
                ],
                steps: [
                    RecipeStep(title: "Mix", instruction: "Whisk the egg and milk, then stir in the oat flour and baking powder until combined."),
                    RecipeStep(title: "Rest batter", instruction: "Let the batter stand for 5 minutes while a nonstick pan warms over medium-low heat.", durationSeconds: 300),
                    RecipeStep(title: "Cook", instruction: "Melt a little butter in the pan. Add small spoonfuls of batter. Turn when bubbles appear and the edges set, then cook until both sides are golden and the centers are set.")
                ],
                sourceName: "Sample recipe", coverAsset: "pancakes", createdAt: created, updatedAt: created
            ),
            Recipe(
                id: UUID(uuidString: "C0010000-0000-4000-8000-000000000004")!,
                title: "Lemon salmon & greens",
                summary: "Pan-cooked salmon with a green salad.",
                servings: 2, prepMinutes: 10, cookMinutes: 15,
                ingredients: [
                    .from(name: "Salmon fillets", amountText: "300 g", category: .proteins),
                    .from(name: "Mixed salad leaves", amountText: "100 g", category: .produce),
                    .from(name: "Lemon", amountText: "1", category: .produce),
                    .from(name: "Olive oil", amountText: "1 tbsp", category: .pantry)
                ],
                steps: [
                    RecipeStep(title: "Prepare", instruction: "Pat the salmon dry. Wash and dry the salad leaves. Cut the lemon into wedges."),
                    RecipeStep(title: "Cook salmon", instruction: "Warm the oil in a pan over medium heat. Start with 5 minutes on the first side, then turn and continue cooking until opaque and cooked through; timing depends on the thickness.", durationSeconds: 300),
                    RecipeStep(title: "Serve", instruction: "Divide the leaves between plates, add the salmon, and finish with fresh lemon juice.")
                ],
                sourceName: "Sample recipe", coverAsset: "salmon", createdAt: created, updatedAt: created
            )
        ]
    }
}
