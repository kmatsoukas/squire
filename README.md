# Squire

Squire is a macOS app, built with SwiftUI, for managing **agent skills**: the folders with a `SKILL.md` file that coding agents such as Claude Code, Codex, opencode, pi and Gemini CLI load to learn new abilities.

Squire lets you:

- **Collect skills from sources.** Add git repositories that contain skills, or map a local folder. Squire scans them and shows every skill it finds in one list.
- **Organise skills.** Tag skills, search them, and disable the ones you do not want offered.
- **Keep sources current.** Download, update (pull) and delete sources.
- **Enable skills globally, per agent.** Squire detects the agents installed on your Mac and links skills into their global skills folder. Agents that share a folder (for example opencode and pi both read `~/.agents/skills`) are grouped together, so a skill is enabled once for all of them.
- **Manage skills per project.** Add project folders and choose the skills each project uses. Squire records them in a lock file inside the project's `.ai` folder, with the source and the exact version (git commit) of every skill, and installs them into the project by symlink or copy. Anyone with Squire can restore the same skills from that file, and you can update them when their source moves on.

## The project lock file

Each managed project gets `.ai/skills.lock.json`:

```json
{
  "agents" : [
    "claude-code",
    "opencode"
  ],
  "installMode" : "symlink",
  "lockfileVersion" : 1,
  "skills" : {
    "pdf" : {
      "path" : "skills/pdf",
      "source" : "https://github.com/anthropics/skills.git",
      "sourceType" : "git",
      "version" : "4f9c2d1e..."
    }
  }
}
```

- `installMode` is `symlink` (links into Squire's versioned store) or `copy` (files copied into the project, good for committing).
- `agents` decides which project folders receive the skills, for example `.claude/skills` or `.agents/skills`.
- `version` is the last git commit that changed the skill's folder, so it only moves when the skill itself changes. Skills from a local folder use `local` and always follow the folder.
- Keys are sorted so the file diffs cleanly when committed.

The folder name `.ai` is a single setting and can change later.

## Project layout

```
Package.swift                 Swift package: app, core library and tests
Sources/
  Squire/                     SwiftUI macOS app (views and app state)
  SquireCore/                 Platform-independent logic: models, git, scanning,
                              agents, installation, lock files, persistence
Tests/
  SquireCoreTests/            Unit tests for SquireCore
```

`SquireCore` depends only on Foundation, so its tests also run on Linux.

## Using Squire

1. **Sources**: add a git repository (for example `https://github.com/anthropics/skills.git`) or a local folder. Squire lists every folder in it that has a `SKILL.md`. Use the refresh button to pull updates.
2. **Skills**: search, filter by tag, and select a skill to tag it, disable it, enable it for an agent, or add it to a project.
3. **Agents**: pick an installed agent (or a folder shared by several agents) and switch skills on or off. Global skills are symlinks to the source checkout, so pulling a source updates them. Folders Squire did not create are listed but never touched.
4. **Projects**: add a project folder from the sidebar. Choose which agents it targets and whether skills are symlinked or copied, then add skills. **Check for Updates** pulls the sources the project uses and shows newer versions; **Update All** moves the pins and reinstalls. **Install** restores everything from the lock file, which is what you run after cloning a project on another Mac.

Settings (⌘,) change the lock file folder and name, and the defaults for new projects.

### Supported agents

| Agent | Global folder | Project folder |
| --- | --- | --- |
| Claude Code | `~/.claude/skills` | `.claude/skills` |
| Codex | `~/.codex/skills` | `.codex/skills` |
| opencode | `~/.agents/skills` | `.agents/skills` |
| pi | `~/.agents/skills` | `.agents/skills` |
| Gemini CLI | `~/.gemini/skills` | `.gemini/skills` |
| Cursor | `~/.cursor/skills` | `.cursor/skills` |
| GitHub Copilot | `~/.copilot/skills` | `.github/skills` |

An agent counts as installed when its config folder exists or its command is on the `PATH`. The list lives in `AgentCatalog` in `Sources/SquireCore/AgentRegistry.swift`, and `LibraryState.customAgents` can add or override agents.

## Building

Requirements: macOS 14 or later and Xcode 15 or later (Swift 5.9+), plus `git` on the `PATH`.

```sh
swift build            # build everything
swift test             # run the SquireCore tests
swift run Squire       # launch the app
```

You can also open `Package.swift` in Xcode and run the `Squire` scheme.

To make a double-clickable app, run `scripts/bundle.sh`, which writes an ad-hoc signed `dist/Squire.app`. CI also uploads this bundle as a build artifact on every push.

## Where Squire keeps its data

- `~/Library/Application Support/Squire/library.json`: sources, tags, disabled skills, projects and settings. Global enablement is read from the agents' skills folders themselves.
- `~/Library/Application Support/Squire/repos/`: clones of git sources, by default. Settings can point this at any folder; existing clones move with it, and repositories already cloned there are added as sources.
- `~/Library/Application Support/Squire/store/`: versioned snapshots of skills used by projects.

## Status

Initial version. See [tasks.md](tasks.md) for what is done.
