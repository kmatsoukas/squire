import SwiftUI
import SquireCore

/// Installed agents, grouped by the skills folder they read, with global skill toggles.
struct AgentsView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedTargetID: SkillTarget.ID?
    @State private var search = ""
    @State private var onlyEnabled = false

    private var selectedTarget: SkillTarget? {
        model.targets.first { $0.id == selectedTargetID } ?? model.targets.first
    }

    private var notInstalled: [AgentDefinition] {
        model.agents.filter { !model.installedAgentIDs.contains($0.id) }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedTargetID) {
                Section("Installed") {
                    ForEach(model.targets) { target in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.displayName)
                                .font(.headline)
                            Text(target.directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if target.agents.count > 1 {
                                Text("Shared folder")
                                    .font(.caption2)
                                    .foregroundStyle(.purple)
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(target.id)
                    }
                }
                if !notInstalled.isEmpty {
                    Section("Not Found") {
                        ForEach(notInstalled) { agent in
                            Text(agent.name)
                                .foregroundStyle(.secondary)
                                .help("Squire looks for \(agent.detectionPaths.joined(separator: ", ")) or the \(agent.executables.joined(separator: ", ")) command.")
                        }
                    }
                }
            }
            .frame(width: 250)

            Divider()

            if let target = selectedTarget {
                TargetSkillsView(target: target, search: search, onlyEnabled: onlyEnabled)
                    .id("\(target.id)-\(model.revision)")
            } else {
                ContentUnavailableView {
                    Label("No Agents Found", systemImage: "person.2.slash")
                } description: {
                    Text("Install an agent such as Claude Code, Codex, opencode or pi, then come back.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Agents")
        .searchable(text: $search, prompt: "Search skills")
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $onlyEnabled) {
                    Label("Only Enabled", systemImage: "checkmark.circle")
                }
                .help("Show only skills enabled for this folder")
            }
        }
    }
}

private struct TargetSkillsView: View {
    @Environment(AppModel.self) private var model
    let target: SkillTarget
    let search: String
    let onlyEnabled: Bool

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        let skills = model.skills.filter { skill in
            if onlyEnabled && !model.isEnabled(skill, in: target) { return false }
            return query.isEmpty
                || skill.name.localizedCaseInsensitiveContains(query)
                || model.tags(for: skill).contains { $0.localizedCaseInsensitiveContains(query) }
        }
        let unmanaged = model.unmanagedEntries(in: target)

        List {
            Section {
                ForEach(skills) { skill in
                    Toggle(isOn: Binding(
                        get: { model.isEnabled(skill, in: target) },
                        set: { model.setEnabled($0, skill: skill, in: target) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(skill.name)
                                ForEach(model.tags(for: skill), id: \.self) { TagChip(text: $0) }
                            }
                            if !skill.description.isEmpty {
                                Text(skill.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(model.isDisabled(skill))
                }
            } header: {
                HStack {
                    Text("Skills for \(target.displayName)")
                    Spacer()
                    Button("Show Folder") { model.reveal(target.directory) }
                        .buttonStyle(.link)
                }
            }

            if !unmanaged.isEmpty {
                Section("Installed Outside Squire") {
                    ForEach(unmanaged, id: \.self) { name in
                        Label(name, systemImage: "folder")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if model.skills.isEmpty {
                ContentUnavailableView("No Skills", systemImage: "sparkles", description: Text("Add a source first."))
            }
        }
    }
}
