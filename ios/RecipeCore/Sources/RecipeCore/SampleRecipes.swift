// Developer: gengyun
// Purpose: Defines deterministic sample recipes used by demos and UI tests.

import Foundation

/// Authored examples are opt-in and remain visibly distinguishable from user imports.
public enum SampleRecipes {
    public static var recipes: [Recipe] {
        let created = Date(timeIntervalSince1970: 1_759_795_200)

        let roastChicken = RecipeIngredient(
            id: UUID(uuidString: "C0051000-0000-4000-8000-000000000001")!,
            name: "Chicken thighs",
            amountText: "600 g",
            quantity: 600,
            unit: "g",
            category: .proteins
        )
        let potatoes = RecipeIngredient(
            id: UUID(uuidString: "C0051000-0000-4000-8000-000000000002")!,
            name: "Baby potatoes",
            amountText: "500 g",
            quantity: 500,
            unit: "g",
            category: .produce
        )
        let oliveOil = RecipeIngredient(
            id: UUID(uuidString: "C0051000-0000-4000-8000-000000000003")!,
            name: "Olive oil",
            amountText: "2 tbsp",
            quantity: 2,
            unit: "tbsp",
            category: .pantry
        )
        let lemon = RecipeIngredient(
            id: UUID(uuidString: "C0051000-0000-4000-8000-000000000004")!,
            name: "Lemon",
            amountText: "1",
            quantity: 1,
            category: .produce
        )
        let garlic = RecipeIngredient(
            id: UUID(uuidString: "C0051000-0000-4000-8000-000000000005")!,
            name: "Garlic",
            amountText: "3 cloves",
            quantity: 3,
            unit: "cloves",
            category: .produce
        )

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
                    RecipeStep(
                        title: "Cook pasta",
                        instruction: "Boil the pasta in water for the time on its package. "
                            + "Start with 10 minutes, check for tenderness, and reserve "
                            + "a small cup of cooking water.",
                        durationSeconds: 600
                    ),
                    RecipeStep(
                        title: "Cook shrimp & toss",
                        instruction: "Melt the butter in a wide pan over medium heat. "
                            + "Cook the shrimp on both sides until opaque and cooked through, "
                            + "then stir in the garlic until fragrant. Toss with the pasta, "
                            + "parsley and a squeeze of lemon. Add reserved cooking water "
                            + "a spoonful at a time to loosen."
                    )
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
                    RecipeStep(
                        title: "Cook",
                        instruction: "Melt a little butter in the pan. Add small spoonfuls "
                            + "of batter. Turn when bubbles appear and the edges set, "
                            + "then cook until both sides are golden and the centers are set."
                    )
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
                    RecipeStep(
                        title: "Cook salmon",
                        instruction: "Warm the oil in a pan over medium heat. Start with "
                            + "5 minutes on the first side, then turn and continue cooking "
                            + "until opaque and cooked through; timing depends on the thickness.",
                        durationSeconds: 300
                    ),
                    RecipeStep(title: "Serve", instruction: "Divide the leaves between plates, add the salmon, and finish with fresh lemon juice.")
                ],
                sourceName: "Sample recipe", coverAsset: "salmon", createdAt: created, updatedAt: created
            ),
            Recipe(
                id: UUID(uuidString: "C0010000-0000-4000-8000-000000000005")!,
                title: "Roast chicken & potatoes",
                summary: "A fuller cooking-mode sample with step ingredients, heat cues and overlapping timers.",
                servings: 4,
                prepMinutes: 20,
                cookMinutes: 45,
                ingredients: [roastChicken, potatoes, oliveOil, lemon, garlic],
                steps: [
                    RecipeStep(
                        title: "Preheat",
                        instruction: "Heat the oven to 220°C while you prepare the tray.",
                        temperature: CookingTemperature(text: "220°C")
                    ),
                    RecipeStep(
                        title: "Season chicken",
                        instruction: "Toss the chicken with half the olive oil, garlic and a squeeze of lemon. Let it stand for 10 minutes.",
                        linkedIngredientIDs: [roastChicken.id, oliveOil.id, garlic.id, lemon.id],
                        timers: [
                            RecipeStepTimer(
                                id: UUID(uuidString: "C0052000-0000-4000-8000-000000000001")!,
                                label: "Marinate chicken",
                                durationSeconds: 600
                            )
                        ]
                    ),
                    RecipeStep(
                        title: "Prepare potatoes",
                        instruction: "Halve the potatoes and toss with the remaining olive oil. Season to taste.",
                        linkedIngredientIDs: [potatoes.id, oliveOil.id]
                    ),
                    RecipeStep(
                        title: "Start roasting",
                        instruction: "Arrange the chicken and potatoes on the hot tray and roast at 220°C for 20 minutes.",
                        linkedIngredientIDs: [roastChicken.id, potatoes.id],
                        temperature: CookingTemperature(text: "220°C"),
                        timers: [
                            RecipeStepTimer(
                                id: UUID(uuidString: "C0052000-0000-4000-8000-000000000002")!,
                                label: "First roast",
                                durationSeconds: 1_200
                            ),
                            RecipeStepTimer(
                                id: UUID(uuidString: "C0052000-0000-4000-8000-000000000003")!,
                                label: "Check tray halfway",
                                durationSeconds: 600
                            )
                        ]
                    ),
                    RecipeStep(
                        title: "Turn and finish",
                        instruction: "Turn the potatoes, spoon the pan juices over the chicken, then roast for 15 minutes more. Check doneness rather than relying on time alone.",
                        linkedIngredientIDs: [roastChicken.id, potatoes.id],
                        temperature: CookingTemperature(text: "220°C"),
                        timers: [
                            RecipeStepTimer(
                                id: UUID(uuidString: "C0052000-0000-4000-8000-000000000004")!,
                                label: "Finish roasting",
                                durationSeconds: 900
                            )
                        ]
                    ),
                    RecipeStep(
                        title: "Rest",
                        instruction: "Move the chicken to a board and rest for 5 minutes before serving.",
                        linkedIngredientIDs: [roastChicken.id],
                        timers: [
                            RecipeStepTimer(
                                id: UUID(uuidString: "C0052000-0000-4000-8000-000000000005")!,
                                label: "Rest chicken",
                                durationSeconds: 300
                            )
                        ]
                    ),
                    RecipeStep(
                        title: "Finish tray",
                        instruction: "Taste the potatoes and pan juices. Add lemon only as needed.",
                        linkedIngredientIDs: [potatoes.id, lemon.id]
                    ),
                    RecipeStep(
                        title: "Serve",
                        instruction: "Slice the chicken and serve with the potatoes and pan juices.",
                        linkedIngredientIDs: [roastChicken.id, potatoes.id]
                    )
                ],
                sourceName: "Sample recipe",
                coverAsset: "salmon",
                createdAt: created,
                updatedAt: created
            )
        ]
    }
}
