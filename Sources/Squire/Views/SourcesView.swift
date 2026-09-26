import SwiftUI
import UniformTypeIdentifiers
import SquireCore

/// Git repositories and local folders that skills come from.
struct SourcesView: View {
    @Environment(AppModel.self) private var model
    @State private var addingGitSource = false
    @State private var choosingFolder = false
    @State private var sourcePendingRemoval: SkillSource?

    var body: some View {
        List {
            ForEach(model.sources) { source in
                SourceRow(source: source)
                    .contextMenu {
                        Button(source.kind == .git ? "Pull Updates" : "Rescan") { model.updateSource(source) }
                        Button("Show in Finder") {
                            if let manager = model.manager { model.reveal(manager.directory(for: source)) }
                        }
                        Divider()
                        Button("Remove…", role: .destructive) { sourcePendingRemoval = source }
                    }
            }
        }
        .overlay {
            if model.sources.isEmpty {
                ContentUnavailableView {
                    Label("No Sources", systemImage: "shippingbox")
                } description: {
                    Text("Add a git repository that contains skills, or a folder on this Mac.")
                } actions: {
                    Button("Add Git Repository…") { addingGitSource = true }
                    Button("Add Local Folder…") { choosingFolder = true }
                }
            }
        }
        .navigationTitle("Sources")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Git Repository…") { addingGitSource = true }
                    Button("Local Folder…") { choosingFolder = true }
                } label: {
                    Label("Add Source", systemImage: "plus")
                }
                Button {
                    model.updateAllSources()
                } label: {
                    Label("Update All", systemImage: "arrow.clockwise")
                }
                .disabled(model.sources.isEmpty)
            }
        }
        .sheet(isPresented: $addingGitSource) {
            AddGitSourceSheet()
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                model.addLocalSource(url)
            }
        }
        .confirmationDialog(
            "Remove \(sourcePendingRemoval?.name ?? "source")?",
            isPresented: Binding(
                get: { sourcePendingRemoval != nil },
                set: { if !$0 { sourcePendingRemoval = nil } }
            ),
            presenting: sourcePendingRemoval
        ) { source in
            Button("Remove", role: .destructive) { model.removeSource(source) }
        } message: { source in
            Text(source.kind == .git
                ? "The clone is deleted and its skills are removed from your agents. Projects keep their pinned copies."
                : "Its skills are removed from your agents. The folder itself is not touched.")
        }
    }
}

struct SourceRow: View {
    @Environment(AppModel.self) private var model
    let source: SkillSource

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: source.kind == .git ? "arrow.triangle.branch" : "folder")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(source.name)
                        .font(.headline)
                    if let branch = source.branch {
                        StatusBadge(text: branch, color: .purple)
                    }
                }
                Text(source.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack(spacing: 10) {
                    Text("\(model.skillCount(for: source)) skills")
                    if let revision = source.revision {
                        Text(revision.shortVersion)
                            .monospaced()
                    }
                    if let date = source.lastUpdated {
                        Text("Updated \(date, style: .relative) ago")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.updateSource(source)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(source.kind == .git ? "Pull updates" : "Rescan folder")
        }
        .padding(.vertical, 4)
    }
}

struct AddGitSourceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var branch = ""
    @State private var name = ""

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Git Repository")
                .font(.title2.bold())
            Form {
                TextField("Repository URL", text: $url, prompt: Text("https://github.com/org/skills.git"))
                TextField("Branch", text: $branch, prompt: Text("Default branch"))
                TextField("Name", text: $name, prompt: Text(trimmedURL.isEmpty ? "From the URL" : SkillManager.repositoryName(from: trimmedURL)))
            }
            Text("Squire clones the repository and lists every folder that contains a SKILL.md file.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    model.addGitSource(url: trimmedURL, branch: branch, name: name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedURL.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
