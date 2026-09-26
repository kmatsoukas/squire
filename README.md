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
  "lockfileVersion": 1,
  "installMode": "symlink",
  "agents": ["claude-code", "opencode"],
  "skills": {
    "pdf": {
      "source": "https://github.com/anthropics/skills.git",
      "path": "skills/pdf",
      "version": "4f9c2d1e..."
    }
  }
}
```

- `installMode` is `symlink` (links into Squire's versioned store) or `copy` (files copied into the project, good for committing).
- `agents` decides which project folders receive the skills, for example `.claude/skills` or `.agents/skills`.
- `version` is the git commit the skill was installed from. Skills from a local folder use `local`.

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

## Building

Requirements: macOS 14 or later and Xcode 15 or later (Swift 5.9+), plus `git` on the `PATH`.

```sh
swift build            # build everything
swift test             # run the SquireCore tests
swift run Squire       # launch the app
```

You can also open `Package.swift` in Xcode and run the `Squire` scheme.

## Where Squire keeps its data

- `~/Library/Application Support/Squire/library.json`: sources, tags, disabled skills, global enablements and projects.
- `~/Library/Application Support/Squire/repos/`: clones of git sources.
- `~/Library/Application Support/Squire/store/`: versioned snapshots of skills used by projects.

## Status

Early development. See [tasks.md](tasks.md) for progress.
