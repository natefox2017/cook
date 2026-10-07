import Foundation
struct Ingredient:Identifiable,Codable,Hashable{var id=UUID();var name:String;var amount:String}
struct RecipeStep:Identifiable,Codable,Hashable{var id=UUID();var text:String;var seconds:Int?}
struct Recipe:Identifiable,Codable,Hashable{var id=UUID();var title:String;var sourceURL:String?;var servings:Int;var minutes:Int;var isFavorite:Bool;var needsReview:Bool;var ingredients:[Ingredient];var steps:[RecipeStep]}
struct GroceryItem:Identifiable,Codable,Hashable{var id=UUID();var name:String;var amount:String;var checked:Bool;var recipeID:UUID?}
struct PersistedState:Codable{var recipes:[Recipe];var groceries:[GroceryItem]}
