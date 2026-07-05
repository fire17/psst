# Changelog

## v0.1.0 — 2026-07-06

Initial release 💡

- `preexec`-based hint engine: pure zsh, zero forks, ~0.26ms per command
- hints on commands (`cmd`), full-command-line globs (`pat`), or any command (`any`)
- many-to-many: comma-separated targets, multiple hints per command shown at random
- per-hint `--cooldown`, `--chance`, `--in <dir>` scoping, tags
- alias-aware and prefix-aware matching (sudo/env/paths)
- lifecycle: `snooze` / `wake` / `done` (learned), per-hint & global on/off
- starter packs: `modern-unix`, `git`, `safety` (+ custom pack files)
- `psst tui` (fzf), `psst try`, `psst stats`, `psst doctor`, `psst demo`
- import/export, atomic writes, malformed-row resilience
- installer, uninstaller, CI, 48-test suite
