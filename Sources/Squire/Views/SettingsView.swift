import SwiftUI
import SquireCore

/// App preferences: where project lock files live and defaults for new projects.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = SquireSettings()
    @State private var loaded = false

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
