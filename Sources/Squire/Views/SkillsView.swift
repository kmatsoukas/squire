import SwiftUI
import SquireCore

/// Every skill from every source, with search, tag filtering and a detail inspector.
struct SkillsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var tagFilter: String?
    @State private var hideDisabled = false
    @State private var selection: Skill.ID?
    @State private var showInspector = true

    private var filteredSkills: [Skill] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return model.skills.filter { skill in
            if hideDisabled && model.isDisabled(skill) { return false }
            if let tagFilter, !model.tags(for: skill).contains(tagFilter) { return false }
            guard !query.isEmpty else { return true }
            return skill.name.localizedCaseInsensitiveContains(query)
                || skill.description.localizedCaseInsensitiveContains(query)
                || model.tags(for: skill).contains { $0.localizedCaseInsensitiveContains(query) }
                || (model.source(for: skill)?.name.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        List(filteredSkills, selection: $selection) { skill in
            SkillRow(skill: skill)
                .tag(skill.id)
        }
        .overlay {
            if model.skills.isEmpty {
                ContentUnavailableView {
                    Label("No Skills Yet", systemImage: "sparkles")
                } description: {
                    Text("Add a git repository or a local folder with skills in Sources.")
                }
            } else if filteredSkills.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, prompt: "Search skills, tags and sources")
        .navigationTitle("Skills")
        .navigationSubtitle("\(model.skills.count) skills")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button {
                        tagFilter = nil
                    } label: {
                        if tagFilter == nil { Label("All Tags", systemImage: "checkmark") } else { Text("All Tags") }
                    }
                    if !model.allTags.isEmpty { Divider() }
                    ForEach(model.allTags, id: \.self) { tag in
                        Button {
                            tagFilter = tag
                        } label: {
                            if tagFilter == tag { Label(tag, systemImage: "checkmark") } else { Text(tag) }
                        }
                    }
                    Divider()
                    Toggle("Hide Disabled Skills", isOn: $hideDisabled)
                } label: {
                    Label(tagFilter ?? "Filter", systemImage: tagFilter == nil
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill")
                }
                .help("Filter by tag")

                Button {
                    model.updateAllSources()
                } label: {
                    Label("Update Sources", systemImage: "arrow.clockwise")
                }
                .help("Pull every git source")

                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
            }
        }
        .inspector(isPresented: $showInspector) {
            Group {
                if let id = selection, let skill = model.skills.first(where: { $0.id == id }) {
                    SkillDetailView(skill: skill)
                } else {
                    ContentUnavailableView("Select a Skill", systemImage: "sparkles")
                }
            }
            .inspectorColumnWidth(min: 280, ideal: 320, max: 460)
        }
    }
}

struct SkillRow: View {
    @Environment(AppModel.self) private var model
    let skill: Skill

    var body: some View {
        let disabled = model.isDisabled(skill)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(skill.name)
                    .font(.headline)
                    .strikethrough(disabled)
                if disabled {
                    StatusBadge(text: "Disabled", color: .secondary)
                }
                Spacer()
                if let source = model.source(for: skill) {
                    Text(source.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !skill.description.isEmpty {
                Text(skill.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            let tags = model.tags(for: skill)
            if !tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(tags, id: \.self) { TagChip(text: $0) }
                }
            }
        }
        .padding(.vertical, 3)
        .opacity(disabled ? 0.6 : 1)
    }
}

/// Details, tags, global enablement and project installs for one skill.
struct SkillDetailView: View {
    @Environment(AppModel.self) private var model
    let skill: Skill
    @State private var newTag = ""

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(skill.name)
                        .font(.title2.bold())
                    if !skill.description.isEmpty {
                        Text(skill.description)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Toggle("Available", isOn: Binding(
                    get: { !model.isDisabled(skill) },
                    set: { model.setDisabled(!$0, skill: skill) }
                ))
                .help("Disabled skills are removed from agents and cannot be added to projects")
            }

            Section("Tags") {
                let tags = model.tags(for: skill)
                if !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags, id: \.self) { tag in
                            TagChip(text: tag) { model.removeTag(tag, from: skill) }
                        }
                    }
                }
                HStack {
                    TextField("Add tag", text: $newTag)
                        .onSubmit(addTag)
                    let suggestions = model.allTags.filter { !tags.contains($0) }
                    if !suggestions.isEmpty {
                        Menu {
                            ForEach(suggestions, id: \.self) { tag in
                                Button(tag) { model.addTag(tag, to: skill) }
                            }
                        } label: {
                            Image(systemName: "tag")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Add an existing tag")
                    }
                }
            }

            Section("Enabled Globally") {
                if model.targets.isEmpty {
                    Text("No installed agents found.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.targets) { target in
                    Toggle(isOn: Binding(
                        get: { model.isEnabled(skill, in: target) },
                        set: { model.setEnabled($0, skill: skill, in: target) }
                    )) {
                        VStack(alignment: .leading) {
                            Text(target.displayName)
                            Text(target.directory.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(model.isDisabled(skill))
                }
            }

            if !model.projects.isEmpty {
                Section("Projects") {
                    Menu("Add to Project") {
                        ForEach(model.projects) { project in
                            Button(project.name) { model.addSkills([skill], to: project) }
                        }
                    }
                    .disabled(model.isDisabled(skill))
                }
            }

            Section("Location") {
                LabeledContent("Source", value: model.source(for: skill)?.name ?? skill.sourceID)
                LabeledContent("Path", value: skill.relativePath.isEmpty ? "/" : skill.relativePath)
                LabeledContent("Installs as", value: skill.installName)
                Button("Show in Finder") { model.reveal(skill.directory) }
            }

            let extra = skill.metadata.filter { $0.key != "name" && $0.key != "description" }
            if !extra.isEmpty {
                Section("Metadata") {
                    ForEach(extra.keys.sorted(), id: \.self) { key in
                        LabeledContent(key, value: extra[key] ?? "")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .id(model.revision)
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }
        model.addTag(tag, to: skill)
        newTag = ""
    }
}
