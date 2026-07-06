# Changelog

## v0.4.0 — 2026-07-06

- **the guard 🛑**: hints that warrant a warning now hold the command behind a live
  Are-you-sure countdown — ⚠️ (or `--warn`) → yellow, 30s; ❗/🚨 (or `--danger`) →
  red ❗⚠️, 60s. Enter = run now, Esc/Ctrl+C = cancel (the command never executes,
  pty-verified), countdown end = auto-run. Roadmap #11, shipped.
- auto-detection from the hint's own text (⚠️→warn, ❗/🚨→danger); `--no-guard` opts out
- `psst guard on|off|status` global switch; `PSST_GUARD=0` per session;
  `PSST_GUARD_WARN`/`PSST_GUARD_DANGER` durations
- safety pack: `rm -rf` and `dd of=/dev/…` are danger-guarded, `chmod 777` and
  `curl | sh` warn-guarded
- guarded hints show in list/show/try (`⚠️ guarded` / `❗ guarded`); demo shows the styles
- 16 new tests (108 total); fixed a zsh `local REPLY` re-declaration output leak

## v0.3.2 — 2026-07-06

- docs: README "What it feels like" showcase (real output of the bundled packs) and
  "Add your own in seconds" — custom hints for any base command, no reload needed

## v0.3.1 — 2026-07-06

- **fix**: a value-taking flag with no value (`psst add --tag`) looped forever — now dies
  with a clear message (guarded in both the add parser and command-scoped add)
- **fix**: `psst <cmd> rm <n>` with an out-of-range number now falls back to treating it
  as a hint id (all-digit ids were unreachable)
- `psst doctor` zshrc check tightened to real plugin wiring (was matching any "psst" text)
- 4 regression tests with a run-deadline guard (92 total)

## v0.3.0 — 2026-07-06

- **per-command mute**: `psst hide <cmd>` silences everything psst does for a base command
  (cmd, pattern and any-hints; alias-aware; instant across sessions); `psst show <cmd>`
  unmutes; bare `psst hide` lists what's muted
- **`psst list` is now a table**: one row per base command with hint count and an example;
  `◇ already using it` marks unless-covered commands; flat view moved to `psst list --full`
- **command-scoped verbs**: `psst <cmd> list` (numbered), `psst <cmd> add <hint…>`,
  `psst <cmd> rm <n>`, `psst <cmd> hide/show/on/off`; `psst any …` manages --any hints
- `psst show <id>` still prints hint details; `psst try` warns when the command is hidden
- 20 new tests (88 total)

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
