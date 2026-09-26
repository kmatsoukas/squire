import SwiftUI
import SquireCore

struct ProjectView: View {
    let project: Project

    var body: some View {
        ContentUnavailableView(project.name, systemImage: "folder")
    }
}
