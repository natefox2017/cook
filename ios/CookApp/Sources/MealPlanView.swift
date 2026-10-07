import SwiftUI
struct MealPlanView:View{
 @Environment(AppStore.self)private var store;@State private var weekOffset=0;@State private var pickingDate:Date?;@State private var meal="Dinner"
 var start:Date{let cal=Calendar.current;let now=cal.date(byAdding:.weekOfYear,value:weekOffset,to:Date())!;return cal.dateInterval(of:.weekOfYear,for:now)!.start}
 var days:[Date]{(0..<7).compactMap{Calendar.current.date(byAdding:.day,value:$0,to:start)}}
 var body:some View{List{Section{HStack{Button{weekOffset-=1}label:{Image(systemName:"chevron.left")};Spacer();Text(start.formatted(.dateTime.month().day())+" – "+days.last!.formatted(.dateTime.month().day()));Spacer();Button{weekOffset+=1}label:{Image(systemName:"chevron.right")}}}
  ForEach(days,id:\.self){day in Section(day.formatted(.dateTime.weekday(.wide).month().day())){ForEach(store.mealPlan.filter{$0.date.sameDay(as:day)}){e in if let r=store.recipes.first(where:{$0.id==e.recipeID}){HStack{VStack(alignment:.leading){Text(r.title);Text("\(e.meal) · \(e.servings) servings").font(.caption).foregroundStyle(.secondary)};Spacer();Button(role:.destructive){store.unplan(e.id)}label:{Image(systemName:"xmark.circle")}}}};Button{pickingDate=day}label:{Label("Add meal",systemImage:"plus")}}}
 }.navigationTitle("Meal Plan").sheet(item:$pickingDate){date in NavigationStack{List{Picker("Meal",selection:$meal){ForEach(["Breakfast","Lunch","Dinner","Snack"],id:\.self){Text($0)}};ForEach(store.recipes){r in Button(r.title){store.plan(recipeID:r.id,date:date,meal:meal,servings:r.servings);pickingDate=nil}}}.navigationTitle("Choose Recipe")}}}
}
extension Date: @retroactive Identifiable{public var id:Double{timeIntervalSinceReferenceDate}}
