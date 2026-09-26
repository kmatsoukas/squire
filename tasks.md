# Squire tasks

Progress on the initial version. Each task is pushed to the `claude/initial-version-7t07za` branch when done.

- [x] Initial README and package structure on `master`
- [x] Create the working branch and this task list
- [ ] CI: build and test on macOS, test SquireCore on Linux
- [ ] Core models: skills, sources, agents, projects, tags
- [ ] SKILL.md frontmatter parser and skill scanner
- [ ] Git client: clone, pull, current commit, snapshot export
- [ ] Agent registry, installed-agent detection and shared-folder grouping
- [ ] Installer: symlink or copy skills into a skills folder, uninstall
- [ ] Versioned skill store for pinned project installs
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
