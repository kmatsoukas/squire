import SwiftUI
import SquireCore

/// A project's lock file: its agents, install mode and pinned skills.
struct ProjectView: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var details: ProjectDetails?
    @State private var addingSkills = false
    @State private var selection = Set<String>()

    var body: some View {
        Group {
            if let details {
                content(details)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(project.name)
        .navigationSubtitle(project.path)
        .task(id: model.revision) {
            details = await model.projectDetails(project)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    addingSkills = true
                } label: {
                    Label("Add Skills", systemImage: "plus")
                }
                .help("Add skills to this project")

                Button {
                    model.checkForUpdates(project)
                } label: {
                    Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Pull the sources this project uses and look for newer versions")

                Button {
                    model.syncProject(project)
                } label: {
                    Label("Install", systemImage: "square.and.arrow.down")
                }
                .help("Install every skill in the lock file at its pinned version")

                Button {
                    model.reveal(project.url)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }
        }
        .sheet(isPresented: $addingSkills) {
            AddProjectSkillsSheet(project: project, existing: Set(details?.lockFile.skills.keys.map { $0 } ?? []))
        }
    }

    @ViewBuilder
    private func content(_ details: ProjectDetails) -> some View {
        let updates = details.statuses.filter(\.hasUpdate)
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Install mode", selection: Binding(
                        get: { details.lockFile.installMode },
                        set: { model.setInstallMode($0, for: project) }
                    )) {
                        Text("Symlink").tag(InstallMode.symlink)
                        Text("Copy").tag(InstallMode.copy)
                    }
                    .pickerStyle(.segmented)
                    .help("Symlink links to Squire's pinned copies. Copy puts the files in the project, so they can be committed.")

                    LabeledContent("Agents") {
                        AgentSelector(project: project, selected: details.lockFile.agents)
                    }

                    LabeledContent("Lock file") {
                        HStack {
                            Text(details.lockFileURL.path.replacingOccurrences(of: project.path + "/", with: ""))
                                .monospaced()
                                .foregroundStyle(.secondary)
                            Button("Show") { model.reveal(details.lockFileURL) }
                                .buttonStyle(.link)
                        }
                    }
                    if !details.targets.isEmpty {
                        LabeledContent("Installs into") {
                            Text(details.targets.map { $0.directory.path.replacingOccurrences(of: project.path + "/", with: "") }.joined(separator: ", "))
                                .monospaced()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 220)

            if !updates.isEmpty {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.blue)
                    Text(updates.count == 1 ? "1 skill has an update." : "\(updates.count) skills have updates.")
                    Spacer()
                    Button("Update All") { model.updateProjectSkills(project) }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.blue.opacity(0.08))
            }

            Table(details.statuses, selection: $selection) {
                TableColumn("Skill") { status in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.name)
                        if let description = status.skill?.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                TableColumn("Source") { status in
                    Text(SkillManager.repositoryName(from: status.locked.source))
                        .help(status.locked.source)
                }
                .width(min: 80, ideal: 120)
                TableColumn("Version") { status in
                    HStack(spacing: 4) {
                        Text(status.locked.version.shortVersion)
                            .monospaced()
                        if status.hasUpdate, let latest = status.latestVersion {
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                            Text(latest.shortVersion)
                                .monospaced()
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .width(min: 80, ideal: 150)
                TableColumn("Status") { status in
                    if !status.isInstalled {
                        StatusBadge(text: "Not installed", color: .orange)
                    } else if status.hasUpdate {
                        StatusBadge(text: "Update available", color: .blue)
                    } else {
                        StatusBadge(text: "Installed", color: .green)
                    }
                }
                .width(min: 90, ideal: 110)
            }
            .contextMenu(forSelectionType: String.self) { names in
                if !names.isEmpty {
                    Button("Update") { model.updateProjectSkills(project, names: Array(names)) }
                    Divider()
                    Button("Remove from Project", role: .destructive) {
                        for name in names { model.removeSkill(named: name, from: project) }
                    }
                }
            }
            .onDeleteCommand {
                for name in selection { model.removeSkill(named: name, from: project) }
                selection.removeAll()
            }
            .overlay {
                if details.statuses.isEmpty {
                    ContentUnavailableView {
                        Label("No Skills", systemImage: "sparkles")
                    } description: {
                        Text("Add skills to pin them in this project's lock file.")
                    } actions: {
                        Button("Add Skills…") { addingSkills = true }
                    }
                }
            }
        }
    }
}

/// Toggles for which agents' project folders receive the skills.
private struct AgentSelector: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let selected: [String]

    var body: some View {
        Menu {
            ForEach(model.agents) { agent in
                Toggle(isOn: Binding(
                    get: { selected.contains(agent.id) },
                    set: { isOn in
                        var agents = selected.filter { $0 != agent.id }
                        if isOn { agents.append(agent.id) }
                        model.setAgents(agents, for: project)
                    }
                )) {
                    Text("\(agent.name)  \(agent.projectSkillsPath)")
                }
            }
        } label: {
            let names = selected.compactMap { id in model.agents.first { $0.id == id }?.name }
            Text(names.isEmpty ? "None" : names.joined(separator: ", "))
        }
        .fixedSize()
    }
}

/// Pick skills from the library to add to a project.
private struct AddProjectSkillsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let project: Project
    let existing: Set<String>
    @State private var search = ""
    @State private var chosen = Set<String>()

    private var candidates: [Skill] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return model.skills.filter { skill in
            guard !model.isDisabled(skill), !existing.contains(skill.installName) else { return false }
            return query.isEmpty
                || skill.name.localizedCaseInsensitiveContains(query)
                || skill.description.localizedCaseInsensitiveContains(query)
                || model.tags(for: skill).contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Skills to \(project.name)")
                .font(.title2.bold())
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
            List(candidates) { skill in
                Toggle(isOn: Binding(
                    get: { chosen.contains(skill.id) },
                    set: { isOn in
                        if isOn { chosen.insert(skill.id) } else { chosen.remove(skill.id) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(skill.name)
                            Text(model.source(for: skill)?.name ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !skill.description.isEmpty {
                            Text(skill.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .frame(minHeight: 300)
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView("No Skills to Add", systemImage: "sparkles")
                }
            }
            HStack {
                Text("Skills are pinned at their latest version.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(chosen.count > 1 ? "Add \(chosen.count) Skills" : "Add") {
                    let skills = model.skills.filter { chosen.contains($0.id) }
                    model.addSkills(skills, to: project)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
    }
}
