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
- [ ] Project lock file (`.ai/skills.lock.json`): read, write, install, update
- [ ] Library persistence and the `SkillManager` facade (sources, tags, disable, global enablement, projects)
- [ ] Unit tests for SquireCore
- [ ] SwiftUI app shell with sidebar navigation
- [ ] Skills view: list, search, tags, enable or disable, source management
- [ ] Agents view: installed agents grouped by folder, enable skills globally
- [ ] Projects view: add projects, manage project skills, sync and update the lock file
- [ ] Settings: lock folder name and default install mode
- [ ] Script to bundle `Squire.app`
- [ ] Update README with usage
