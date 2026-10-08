// Developer: gengyun
// Purpose: Prototype shared colors and visual styling.

import SwiftUI
enum CookTheme {
 static let green=Color(red:0.16,green:0.42,blue:0.25)
 static let paper=Color(red:0.98,green:0.97,blue:0.93)
 static func title(_ size:CGFloat=34)->Font{.system(size:size,weight:.semibold,design:.serif)}
}
struct PrimaryButtonStyle:ButtonStyle{
 func makeBody(configuration:Configuration)->some View{configuration.label.font(.headline).frame(maxWidth:.infinity).padding(.vertical,14).foregroundStyle(.white).background(CookTheme.green.opacity(configuration.isPressed ? 0.78:1),in:Capsule())}
}
