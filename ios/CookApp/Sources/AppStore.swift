// Developer: gengyun
// Purpose: Prototype local store for recipes, groceries, and meal plans.

import Foundation
import Observation
@Observable final class AppStore {
 private(set)var recipes:[Recipe]=[];private(set)var groceries:[GroceryItem]=[];private(set)var mealPlan:[MealPlanEntry]=[];var lastError:String?
 private let fileURL:URL
 init(fileURL:URL?=nil){let base=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!;self.fileURL=fileURL ?? base.appendingPathComponent("cook-state.json");load();if recipes.isEmpty{recipes=Self.samples}}
 func toggleFavorite(_ id:UUID){guard let i=recipes.firstIndex(where:{$0.id==id})else{return};recipes[i].isFavorite.toggle();save()}
 func upsert(_ recipe:Recipe){if let i=recipes.firstIndex(where:{$0.id==recipe.id}){recipes[i]=recipe}else{recipes.insert(recipe,at:0)};save()}
 func importURL(_ raw:String)->Recipe?{let text=raw.trimmingCharacters(in:.whitespacesAndNewlines);guard let url=URL(string:text),["http","https"].contains(url.scheme?.lowercased() ?? "")else{lastError="Enter a valid http or https link.";return nil};if let old=recipes.first(where:{$0.sourceURL==url.absoluteString}){return old};let host=url.host?.replacingOccurrences(of:"www.",with:"") ?? "Web";let r=Recipe(title:"Imported from \(host)",sourceURL:url.absoluteString,servings:2,minutes:0,isFavorite:false,needsReview:true,ingredients:[],steps:[]);upsert(r);return r}
 func addGroceries(from recipe:Recipe,servings:Int){let factor=Double(servings)/Double(max(recipe.servings,1));for x in recipe.ingredients{let amount=factor==1 ? x.amount:x.amount+" × "+String(format:"%.1f",factor);if !groceries.contains(where:{$0.name.caseInsensitiveCompare(x.name)==.orderedSame && $0.recipeID==recipe.id}){groceries.append(GroceryItem(name:x.name,amount:amount,aisle:x.aisle,checked:false,recipeID:recipe.id))}};save()}
 func addManualGrocery(_ name:String){let v=name.trimmingCharacters(in:.whitespacesAndNewlines);guard !v.isEmpty else{return};groceries.append(GroceryItem(name:v,amount:"",checked:false,recipeID:nil));save()}\n func plan(recipeID:UUID,date:Date,meal:String,servings:Int){mealPlan.removeAll{$0.date.sameDay(as:date)&&$0.meal==meal};mealPlan.append(MealPlanEntry(date:date,meal:meal,recipeID:recipeID,servings:servings));save()}\n func unplan(_ id:UUID){mealPlan.removeAll{$0.id==id};save()}\n func addPlannedGroceries(){for e in mealPlan{if let r=recipes.first(where:{$0.id==e.recipeID}){addGroceries(from:r,servings:e.servings)}}}\n func toggleGrocery(_ id:UUID){guard let i=groceries.firstIndex(where:{$0.id==id})else{return};groceries[i].checked.toggle();save()}
 func clearChecked(){groceries.removeAll(where:\.checked);save()}
 private func load(){guard let d=try? Data(contentsOf:fileURL),let s=try? JSONDecoder().decode(PersistedState.self,from:d)else{return};recipes=s.recipes;groceries=s.groceries;mealPlan=s.mealPlan}
 private func save(){do{try FileManager.default.createDirectory(at:fileURL.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONEncoder().encode(PersistedState(recipes:recipes,groceries:groceries,mealPlan:mealPlan)).write(to:fileURL,options:.atomic);lastError=nil}catch{lastError="Changes could not be saved."}}
 static let samples:[Recipe]=[
  Recipe(title:"Tomato Basil Pasta",sourceURL:nil,servings:2,minutes:25,isFavorite:true,needsReview:false,ingredients:[Ingredient(name:"Spaghetti",amount:"200 g"),Ingredient(name:"Tomatoes",amount:"3"),Ingredient(name:"Basil",amount:"a handful")],steps:[RecipeStep(text:"Boil the pasta until al dente.",seconds:480),RecipeStep(text:"Cook tomatoes until softened.",seconds:300),RecipeStep(text:"Toss with basil and serve.",seconds:nil)]),
  Recipe(title:"Lemon Roast Chicken",sourceURL:nil,servings:4,minutes:55,isFavorite:false,needsReview:false,ingredients:[Ingredient(name:"Chicken thighs",amount:"4"),Ingredient(name:"Lemon",amount:"1")],steps:[RecipeStep(text:"Season the chicken.",seconds:nil),RecipeStep(text:"Roast until browned and cooked through.",seconds:2100)])
 ]
}

extension Date{func sameDay(as other:Date)->Bool{Calendar.current.isDate(self,inSameDayAs:other)}}
