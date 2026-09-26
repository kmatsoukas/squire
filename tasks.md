# Squire tasks

Progress on the initial version. Each task is pushed to the `claude/initial-version-7t07za` branch when done.

- [x] Initial README and package structure on `master`
- [x] Create the working branch and this task list
- [x] CI: build and test on macOS, test SquireCore on Linux
- [x] Core models: skills, sources, agents, projects, tags
- [x] SKILL.md frontmatter parser and skill scanner
- [x] Git client: clone, pull, current commit, snapshot export
- [x] Agent registry, installed-agent detection and shared-folder grouping
- [x] Installer: symlink or copy skills into a skills folder, uninstall
- [x] Versioned skill store for pinned project installs
- [x] Project lock file (`.ai/skills.lock.json`) format: read and write
- [x] Library persistence and the `SkillManager` facade (sources, tags, disable, global enablement)
- [x] Project skills: add, remove, sync from the lock file, check for and apply updates
- [x] Unit tests for SquireCore
- [x] SwiftUI app shell with sidebar navigation
- [x] Skills view: list, search, tags, enable or disable, source management
- [x] Agents view: installed agents grouped by folder, enable skills globally
- [x] Projects view: add projects, manage project skills, sync and update the lock file
- [x] Settings: lock folder name and default install mode
- [x] Script to bundle `Squire.app`
- [ ] Update README with usage
