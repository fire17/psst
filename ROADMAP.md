# psst roadmap 🗺️

Ranked by priority — a blend of value, effort, and how much each unlocks the next thing.
Effort: **S** ≤ half a day · **M** a day or two · **L** a project.

## P0 — missing basics (do next)

| # | Feature | Why it matters | Effort |
|---|---|---|---|
| 1 | **zsh tab completions** — complete subcommands, hint ids, base commands, pack names, durations | The CLI grew real surface area; completions are the difference between "tool" and "product" | S |
| 2 | **`psst edit <id>` + `psst set <id> --cooldown 1h --chance 50 …`** — edit one hint without opening the whole TSV | Editing a hint today means `psst edit` (whole file) or rm+re-add | S |
| 3 | **`psst undo`** — snapshot the store before every write, restore the last one | `rm --all`, `pack remove`, scoped `rm` are one typo away from loss; trust needs a safety net | S |
| 4 | **`psst scan`** — read shell history, find your habits (e.g. `git checkout -b` used 40×), propose matching hints/packs interactively | Turns onboarding from "think of hints" into "accept suggestions"; the killer first-run experience | M |
| 5 | **DND / meeting mode** — `psst snooze all 2h`, `psst quiet` (per-session already exists; this is global & timed) | Screen-sharing, demos, recordings — you want silence *now*, everywhere, without uninstalling | S |
| 6 | **Exit-code coach (127)** — a `precmd` hook: when a command fails with *command not found*, whisper the install line or the alternative you already have | psst currently only knows what you typed; knowing what *failed* is the highest-signal moment to help | M |
| 7 | **Validate patterns & fields at add-time** — warn on malformed globs, tabs, bad chance/cooldown | Bad rows silently never fire; fail at write time, not at whisper time | S |

## P1 — UX force multipliers

| # | Feature | Why it matters | Effort |
|---|---|---|---|
| 8 | **Anti-repeat rotation** — never show the same hint twice in a row when siblings exist | Random with replacement feels broken exactly when you add multiple hints | S |
| 9 | **Adaptive decay** — the more a hint has fired, the less often it shows (log-scale), until `done` | Nagging kills goodwill; hints should fade as they teach | M |
| 10 | **Auto-graduation 🎓** — if you start typing the *suggested* tool regularly, auto-`done` the hint and congratulate once | Closes the learning loop by itself; the product's soul, automated | M |
| 11 | **`--confirm` hints** — safety-pack escalation: require Enter (or y) before the command runs, not just a 1s pause | Turns the safety pack into a real guardrail for `rm -rf` / `dd` / force-push | M |
| 12 | **bash & fish ports** — bash-preexec / fish `fish_preexec` event, same data files | Doubles the audience; the store format is already shell-agnostic | L |
| 13 | **`psst config`** — get/set styling, gaps, pause defaults from the CLI (writes config.zsh) | Editing a config file is friction; every option should be one command away | S |
| 14 | **Quiet hours** — `psst quiet-hours 22:00-09:00`, plus a `when=` time window per hint | Late-night you does not want productivity tips | S |
| 15 | **TUI v2** — add-hint form, live search, pack browser, stats view; graceful no-fzf fallback menu | The TUI is the discovery surface; today it's browse-only | M |
| 16 | **Did-you-mean** — `psst lst` → "did you mean list?" (before falling through to command-scope) | The scope fallback is powerful but makes typos silent; catch obvious ones | S |
| 17 | **`psst update`** — self-update via git pull / brew upgrade hint, with changelog display | Keeping people current is how packs and fixes actually reach them | S |
| 18 | **Cross-pane dedupe** — global MIN_GAP shared via state file so 4 tmux panes ≠ 4× the same whisper | Heavy tmux users (like this repo's author 👋) feel hint-spam multiplicatively | S |

## P2 — sharing & ecosystem

| # | Feature | Why it matters | Effort |
|---|---|---|---|
| 19 | **Remote packs** — `psst pack install gh:user/repo[/pack]`, pinned & updatable | Packs are the network effect; installing from a URL makes them shareable artifacts | M |
| 20 | **Team sync** — `psst sync <git-url>`: a shared hints repo merged on top of personal ones ("this repo uses pnpm", "deploy = make ship") | Onboarding new teammates via whispers-in-context beats a wiki nobody reads | M |
| 21 | **More stack packs** — docker, kubernetes, npm→pnpm, python→uv, rust, macos | Each pack is an acquisition channel and instant value | S each |
| 22 | **`psst list --json` + `psst emit "…"`** — machine-readable output and a pipe for *other tools* to whisper through psst (respecting mutes/cooldowns/pause) | This is the "part of a larger system" socket: anything can become a hint source | M |
| 23 | **Hint metadata: `--note <url>` and `--expires <date>`** — learn-more links; self-deleting reminders ("migrate the server by Friday!") | Hints as lightweight, self-cleaning sticky notes | S |
| 24 | **Weekly digest / streaks** — `psst progress`: "grep 14× vs rg 3× — trending right", shown once on Monday's first shell | Progress you can see is motivation to keep the tool installed | M |

## P3 — novel bets

| # | Feature | Why it matters | Effort |
|---|---|---|---|
| 25 | **Press-to-swap** — a zle widget: after "psst · use fresh", press a hotkey to *run the suggestion instead* of the typed command | From advice to action in one keystroke; nothing else does this | L |
| 26 | **AI hint generation** — `psst ai "I keep forgetting tar flags"` → drafts hints; or analyze history and propose a personalized pack | Personalized > curated; pairs naturally with `psst scan` | M |
| 27 | **Context conditions registry** — `when=git-dirty`, `when=ssh`, `when=battery`, `when=repo:foo` … pluggable, AND-composed like everything else | Right hint, right moment — context is the next matching dimension after command & directory | L |
| 28 | **Slow-command tips** — command took >30s? Once, suggest the faster alternative or `&`/nohup patterns | Latency pain is the most teachable moment after failure | M |
| 29 | **Post-command coaching** — `precmd` hints keyed on (command, exit code): "that grep found nothing — try rg --hidden" | Reacting to outcomes, not just intentions — the second half of the loop | L |
| 30 | **Multi-machine sync** — hints/state as a dotfiles-friendly git dir with merge (`psst sync push/pull`) | Your whispers should follow you to every box you SSH into | M |

---

*Want one of these? Open an issue — or a PR. Packs are just TSV files; conditions and verbs are
registry entries by design.*
