import SwiftUI
import SquireCore

@main
struct SquireApp: App {
    var body: some Scene {
        WindowGroup("Squire") {
            Text("Squire \(SquireCore.version)")
                .frame(minWidth: 600, minHeight: 400)
        }
    }
}
