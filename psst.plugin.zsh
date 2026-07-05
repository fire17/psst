# psst — gentle hints for your shell, right before you need them.
# https://github.com/fire17/psst
#
# Standard zsh plugin entry point. Works with zinit, oh-my-zsh, antidote,
# zplug, or a plain `source` line in ~/.zshrc.

0=${(%):-%N}
typeset -g PSST_ROOT=${0:A:h}

source "$PSST_ROOT/lib/core.zsh"

# Lazy first load: the hook detects the empty signature and parses the hints
# file on the first command, so plugin sourcing itself costs ~nothing.
autoload -Uz add-zsh-hook
add-zsh-hook preexec _psst_preexec

# Make the `psst` CLI reachable without a separate install step.
if (( ! ${path[(Ie)$PSST_ROOT/bin]} )); then
  path+=("$PSST_ROOT/bin")
fi

# Optional user config (styling, gaps, stats toggle).
[[ -r "$PSST_DIR/config.zsh" ]] && source "$PSST_DIR/config.zsh"
