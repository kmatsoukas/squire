import SwiftUI
import UniformTypeIdentifiers
import SquireCore

enum SidebarItem: Hashable {
    case skills
    case sources
    case agents
    case project(UUID)
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .skills
    @State private var choosingProject = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Library") {
                    Label("Skills", systemImage: "sparkles")
                        .tag(SidebarItem.skills)
                    Label("Sources", systemImage: "shippingbox")
                        .tag(SidebarItem.sources)
                    Label("Agents", systemImage: "person.2")
                        .tag(SidebarItem.agents)
                }
                Section("Projects") {
                    ForEach(model.projects) { project in
                        Label(project.name, systemImage: "folder")
                            .tag(SidebarItem.project(project.id))
                            .help(project.path)
                            .contextMenu {
                                Button("Show in Finder") { model.reveal(project.url) }
                                Divider()
                                Button("Remove from Squire", role: .destructive) {
                                    if selection == .project(project.id) { selection = .skills }
                                    model.removeProject(project)
                                }
                            }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                Button {
                    choosingProject = true
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fileImporter(isPresented: $choosingProject, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    model.addProject(url)
                }
            }
        } detail: {
            switch selection {
            case .skills, .none:
                SkillsView()
            case .sources:
                SourcesView()
            case .agents:
                AgentsView()
            case .project(let id):
                if let project = model.projects.first(where: { $0.id == id }) {
                    ProjectView(project: project)
                        .id(project.id)
                } else {
                    ContentUnavailableView("No Project Selected", systemImage: "folder")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let activity = model.activity {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(activity)
                        .font(.callout)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: model.activity)
        .alert("Something went wrong", isPresented: errorIsPresented) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

/// A small rounded label for a tag.
struct TagChip: View {
    let text: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Remove tag")
            }
        }
        .font(.caption)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.15), in: Capsule())
        .foregroundStyle(Color.accentColor)
    }
}

/// A colored status label, for example "Update available".
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

extension String {
    /// First seven characters of a commit hash; other versions unchanged.
    var shortVersion: String {
        count == 40 ? String(prefix(7)) : self
    }
}
