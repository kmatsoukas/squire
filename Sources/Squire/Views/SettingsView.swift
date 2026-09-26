import SwiftUI
import UniformTypeIdentifiers
import SquireCore

/// App preferences: where project lock files live and defaults for new projects.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = SquireSettings()
    @State private var loaded = false
    @State private var choosingRepositoriesFolder = false

    var body: some View {
        Form {
            Section("Project lock file") {
                TextField("Folder", text: $draft.projectFolderName, prompt: Text(".ai"))
                TextField("File name", text: $draft.lockFileName, prompt: Text("skills.lock.json"))
                Text("Projects keep their skills in \(draft.projectFolderName)/\(draft.lockFileName). Existing projects are not moved when this changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("New projects") {
                Picker("Install mode", selection: $draft.defaultInstallMode) {
                    Text("Symlink").tag(InstallMode.symlink)
                    Text("Copy").tag(InstallMode.copy)
                }
                ForEach(model.agents) { agent in
                    Toggle(agent.name, isOn: Binding(
                        get: { draft.defaultProjectAgents.contains(agent.id) },
                        set: { isOn in
                            draft.defaultProjectAgents.removeAll { $0 == agent.id }
                            if isOn { draft.defaultProjectAgents.append(agent.id) }
                        }
                    ))
                }
            }

            Section("Git repositories") {
                LabeledContent("Clone into") {
                    HStack {
                        Text(repositoriesPathLabel)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { choosingRepositoriesFolder = true }
                        if draft.repositoriesPath != nil {
                            Button("Default") { draft.repositoriesPath = nil }
                        }
                    }
                }
                Text("Git sources are cloned here and their skills are read from the clones. Changing the folder moves existing clones, and repositories already cloned in the new folder are added as sources.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fileImporter(isPresented: $choosingRepositoriesFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    draft.repositoriesPath = url.path
                }
            }

            if let manager = model.manager {
                Section("Library") {
                    LabeledContent("Data folder") {
                        Button(manager.paths.supportDirectory.path) {
                            model.reveal(manager.paths.supportDirectory)
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Revert") { draft = model.settings }
                    .disabled(draft == model.settings)
                Button("Save") { model.updateSettings(cleaned(draft)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft == model.settings)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if !loaded {
                draft = model.settings
                loaded = true
            }
        }
    }

    private var repositoriesPathLabel: String {
        if let path = draft.repositoriesPath, !path.isEmpty {
            return path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
        return "Default (Application Support)"
    }

    private func cleaned(_ settings: SquireSettings) -> SquireSettings {
        var result = settings
        let defaults = SquireSettings()
        result.projectFolderName = result.projectFolderName.trimmingCharacters(in: .whitespaces)
        result.lockFileName = result.lockFileName.trimmingCharacters(in: .whitespaces)
        if result.projectFolderName.isEmpty { result.projectFolderName = defaults.projectFolderName }
        if result.lockFileName.isEmpty { result.lockFileName = defaults.lockFileName }
        return result
    }
}
