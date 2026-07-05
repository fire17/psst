#!/bin/sh
# psst installer — https://github.com/fire17/psst
# Installs the plugin and wires it into ~/.zshrc (marked block, easy to remove:
# `psst uninstall`). Safe to re-run.
set -e

REPO="https://github.com/fire17/psst"
DEFAULT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/psst"

say() { printf '%s\n' "$*"; }

# If run from inside a checkout, install from here; otherwise clone/update.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || SCRIPT_DIR=""
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/psst.plugin.zsh" ]; then
  PSST_HOME="$SCRIPT_DIR"
  say "installing from local checkout: $PSST_HOME"
else
  PSST_HOME="$DEFAULT_DIR"
  if [ -d "$PSST_HOME/.git" ]; then
    say "updating $PSST_HOME"
    git -C "$PSST_HOME" pull --ff-only --quiet
  else
    say "cloning into $PSST_HOME"
    git clone --depth 1 --quiet "$REPO" "$PSST_HOME"
  fi
fi

ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
if grep -qs "psst.plugin.zsh" "$ZSHRC"; then
  say "already wired into $ZSHRC ✓"
else
  {
    printf '\n# >>> psst >>>  (gentle hints for your shell — `psst help`)\n'
    printf 'source "%s/psst.plugin.zsh"\n' "$PSST_HOME"
    printf '# <<< psst <<<\n'
  } >> "$ZSHRC"
  say "added psst block to $ZSHRC ✓"
fi

say ""
say "done! open a new shell, then try:"
say "  psst add nano \"Use fresh for a more modern file editor! :D\""
say "  psst pack install modern-unix"
say "  psst help"
