# Changelog

## v0.2.0 — 2026-07-06

- **breather pause**: the first time a hint fires for a command each day, the command is
  held for 1s so the hint gets read (once per base command, resets daily, shared across
  sessions; forkless `zselect` sleep). `psst pause on|off|status|<seconds>` controls it
  globally; `PSST_PAUSE` per session
- **already-in-use suppression**: `unless=<tool>` tags (and `psst add --unless <tool>`)
  skip hints when the suggested tool is already installed/active; alias-redirect detection
  suppresses hints on names your aliases already point elsewhere (`alias cat='bat'`)
- pack format now carries a tags column (6 cols); bundled zoxide hint is `unless=zoxide`
- `psst status` shows pause state; 20 new tests (68 total)

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
