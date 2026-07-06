# psst 💡

> gentle hints for your shell, right before you need them.

[![CI](https://github.com/fire17/psst/actions/workflows/ci.yml/badge.svg)](https://github.com/fire17/psst/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-pink.svg)](LICENSE)
![zsh 5.3+](https://img.shields.io/badge/zsh-5.3+-blue.svg)

You *know* there's a better tool. You installed it. You read about it at 2am and said "I'm using this from now on."
And then your fingers typed `nano` again.

**psst** whispers a hint right before your command runs:

```
$ nano notes.txt
💡 psst · Use fresh for a more modern file editor! :D
  … nano opens exactly as normal …
```

Your command is **never touched** — no wrappers, no aliases, no quoting weirdness.
psst listens via zsh's `preexec` hook, prints one colorful line, and gets out of the way.

## Install

**One-liner:**

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/fire17/psst/main/install.sh)"
```

*(psst's own safety pack would tell you to read scripts before piping them — [it's short](install.sh) 😉)*

**zinit** · `zinit light fire17/psst`
**oh-my-zsh** · `git clone https://github.com/fire17/psst ~/.oh-my-zsh/custom/plugins/psst` then add `psst` to `plugins=(...)`
**antidote** · `antidote install fire17/psst`
**manual** · clone anywhere and add `source /path/to/psst/psst.plugin.zsh` to `~/.zshrc`

Open a new shell, then take it for a spin:

```sh
psst add nano "Use fresh for a more modern file editor! :D"
psst pack install modern-unix
nano whatever.txt        # 💡
```

## Why

Muscle memory is stronger than memory. psst turns the commands you *already type* into
triggers for the things you *want to remember* — new tools, better flags, safety
double-checks, or anything else ("psst · the deploy checklist is in NOTES.md").

When a hint has done its job: `psst done <id>` — learned, archived, quiet. 🎓

## Everything it can do

```sh
# one hint, many commands (comma-separated) — and many hints per command (shown at random)
psst add nano,pico,vi "micro is nano evolved (brew install micro)"
psst add nano "or try helix — modal editing without the vim cliff"

# match whole command lines with zsh globs — catch the flag, not just the command
psst add --pat 'git push *(-f|--force)(| *)' "--force-with-lease refuses to clobber teammates"

# fire on ANY command — occasional reminders
psst add --any --chance 2 --cooldown 4h "stretch. water. posture. 🌱"

# only inside a project
psst add --in ~/work/big-app npm "this repo uses pnpm!"

# rate control per hint
psst add --cooldown 30m cat "bat is cat with wings"

# suppress a hint wherever the suggested tool is already installed/active
psst add --unless zoxide cd "zoxide learns your dirs — z proj jumps anywhere"

# browse: a table of commands, then drill in
psst list            # one row per command: count + example hint
psst nano list       # numbered hints for one command
psst nano add "or helix — modal editing without the vim cliff"
psst nano rm 2       # remove its 2nd hint
psst hide nano       # mute EVERYTHING psst does for nano…
psst show nano       # …and bring it back (psst hide lists what's muted)

# lifecycle
psst tui             # fzf manager               psst list --full  # every hint, flat
psst snooze 3fa2 7d  # mute for a week           psst wake 3fa2
psst done 3fa2       # learned it — archive      psst on / off     # ALL of psst, globally
psst pause off       # kill the 1s breather      psst pause 2      # or make it longer
psst try "git push -f"   # debug: which hints would fire?
psst stats           # what actually fires, how often
psst export team.tsv / import team.tsv   # share hint sets
```

### The breather ⏸️

The first time a hint fires for a command each day, psst holds the command for **1 second**
so you actually read the hint before output scrolls it away (and get a beat to Ctrl-C on the
safety ones). Every later run that day starts instantly — the pause is once per base command,
resets daily, shared across all your sessions. `psst pause off|on|<seconds>` controls it
globally, `PSST_PAUSE=0` per session.

### Already using the better tool? psst stays quiet

- **`unless=` hints** skip themselves when the suggested tool is already present — installed
  binary, shell function, or alias. The bundled zoxide hint won't nag you if zoxide is
  already wrapping your `cd`.
- **Alias-redirect detection**: if you type `cat` but your `alias cat='bat'` already redirects
  it, hints registered on `cat` are suppressed — you've clearly upgraded. (Hints for `bat`
  itself still work through the alias.)
- `psst list` marks fully-covered commands with `◇ already using it` instead of pretending
  they'd fire.

Session controls: `PSST_QUIET=1` mutes the current shell; `PSST_MIN_GAP=30` shows at most one
hint per 30s globally.

### Hint packs

Curated starter sets, one command away (`psst pack list`):

| pack | what it does |
|---|---|
| `modern-unix` | `cat`→bat, `ls`→eza, `grep`→ripgrep, `find`→fd, `top`→btop, `man`→tldr… |
| `git` | `--force`→`--force-with-lease`, `checkout`→`switch`, prettier `log`, safer `reset` |
| `safety` | a tap on the shoulder before `rm -rf`, `chmod 777`, `dd of=/dev/…`, `curl \| sh` |

`psst pack install modern-unix git safety` · remove anytime with `psst pack remove <name>`.
A pack is just a 6-column TSV — make your own and `psst pack install ./team-pack.tsv`.

## Seamless, really

- Fires behind `sudo`, env prefixes (`FOO=1 cmd`), absolute paths, and **aliases**
  (psst sees the expanded command too — hint on `nano` even when you typed your `n` alias).
- Prints to **stderr** on interactive shells only — pipes, scripts, and subshells never see it.
- The hook **cannot break your shell**: every path returns 0, malformed data is skipped.
- **Fast**: pure zsh, zero forks, zero subshells on the hot path — measured **~0.26ms** per
  command (with 25 hints loaded), and the hints file is only re-parsed when it actually changes.

## Data & config

Everything lives in two small places you own:

- hints: `~/.config/psst/hints.tsv` — one hint per line, 9 tab-separated columns (`psst edit`)
- config: `~/.config/psst/config.zsh` — optional styling:

```zsh
PSST_ICON="✨"                 # default 💡
PSST_PREFIX="hey"              # default psst
PSST_STYLE=$'\e[1;36m'         # prefix style   (default: bold pink 213)
PSST_BODY_STYLE=$'\e[0;36m'    # hint style
PSST_MIN_GAP=0                 # min seconds between any two hints
PSST_STATS=1                   # log fires for `psst stats` (0 to disable)
PSST_PAUSE=1                   # first-hint-of-the-day breather, seconds (0 = off;
                               # prefer `psst pause …` to change it everywhere at once)
```

`psst doctor` checks your whole setup; `psst demo` previews styling.

## Uninstall

```sh
psst uninstall           # removes the ~/.zshrc block, keeps your hints
psst uninstall --purge   # removes hints & stats too
```

## Roadmap

psst is designed as the first piece of a larger "terminal companion" system:

- bash & fish support (via bash-preexec / fish's `fish_preexec`)
- community pack registry (`psst pack install gh:user/repo`)
- context-aware hints (git state, time of day, exit-code-triggered "psst: try tldr xyz?")
- programmatic feed — other tools teaching psst what to whisper

PRs and pack contributions welcome 💛

## License

[MIT](LICENSE) © fire17
