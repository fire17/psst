# psst core — shared by the preexec hook and the CLI.
# Pure zsh, ZERO forks on the hot path (no subshells, no external commands).
#
# hints.tsv columns (tab-separated, placeholders required — never leave a field empty):
#   1 id       4-hex row id
#   2 on       1 | 0
#   3 kind     cmd | pat | any
#   4 targets  cmd: comma-separated command names   pat: zsh glob vs full line   any: -
#   5 cooldown seconds before the same hint may show again this session (0 = always)
#   6 chance   1-100 percent chance to show when matched (100 = always)
#   7 until    unix epoch the hint is snoozed until (0 = not snoozed)
#   8 tags     comma-separated; special: pack:<name>, in=<dir-prefix>; - for none
#   9 hint     the hint text (rest of line)

: ${PSST_DIR:="${XDG_CONFIG_HOME:-$HOME/.config}/psst"}
: ${PSST_HINTS:="$PSST_DIR/hints.tsv"}
: ${PSST_STATE_DIR:="${XDG_STATE_HOME:-$HOME/.local/state}/psst"}

zmodload -F zsh/stat b:zstat 2>/dev/null
zmodload -F zsh/files b:zf_mkdir 2>/dev/null
zmodload -F zsh/zselect b:zselect 2>/dev/null
zmodload zsh/datetime 2>/dev/null

typeset -gA _psst_cmd_map     # command name -> $'\x1e'-joined records
typeset -ga _psst_pat_list    # "pattern \x1f record" entries
typeset -ga _psst_any_list    # records
typeset -gA _psst_last_shown  # hint id -> epoch last shown (this session)
typeset -g  _psst_sig=""      # mtime:size:inode signature of the loaded hints file
typeset -g  _psst_last_any=0  # epoch any hint was last shown (global gap)
typeset -gA _psst_paused      # base command -> 1 if already paused today
typeset -g  _psst_paused_day=""
typeset -g  _psst_paused_sig=""
typeset -gA _psst_hidden      # base command -> 1 if psst is muted for it
typeset -g  _psst_hidden_sig=""
typeset -g  _psst_guard_result=""  # proceed | cancel — set by _psst_guard

# _psst_file_sig — sets REPLY to the hints file signature ("missing" if unreadable)
_psst_file_sig() {
  local -A st
  if zstat -H st -- "$PSST_HINTS" 2>/dev/null; then
    REPLY="${st[mtime]}:${st[size]}:${st[inode]}"
  else
    REPLY="missing"
  fi
}

# _psst_hidden_load — refresh the per-command mute set from $PSST_DIR/hidden
# (one command name per line). Caller handles mtime-gating.
_psst_hidden_load() {
  _psst_hidden=()
  local line
  [[ -r $PSST_DIR/hidden ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z $line || $line == \#* ]] && continue
    _psst_hidden[$line]=1
  done < "$PSST_DIR/hidden"
  return 0
}

# _psst_guard_level <tags> <hint-text> — sets REPLY to - | warn | danger.
# Explicit confirm= tag wins; otherwise the hint's own emoji vocabulary is the
# signal: ❗/🚨 mean danger, ⚠️ means warn. confirm=off opts out entirely.
_psst_guard_level() {
  REPLY="-"
  local tag
  if [[ $1 == *confirm=* ]]; then
    for tag in ${(s:,:)1}; do
      case $tag in
        confirm=danger) REPLY=danger; return 0 ;;
        confirm=warn)   REPLY=warn;   return 0 ;;
        confirm=off|confirm=none) return 0 ;;
      esac
    done
  fi
  case $2 in
    (*❗*|*🚨*) REPLY=danger ;;
    (*⚠*)      REPLY=warn ;;
  esac
  return 0
}

# record layout, $'\x1f'-separated: id cooldown chance until dir guard hint
_psst_load() {
  emulate -L zsh
  _psst_cmd_map=() _psst_pat_list=() _psst_any_list=()
  local REPLY
  _psst_file_sig
  _psst_sig=$REPLY
  [[ $_psst_sig == missing ]] && return 0
  local id on kind targets cooldown chance snooze tags hint
  local rec t dir tag u skip guard
  while IFS=$'\t' read -r id on kind targets cooldown chance snooze tags hint || [[ -n $id ]]; do
    [[ -z $id || $id == \#* ]] && continue
    [[ $on == 1 ]] || continue
    dir="-" skip=0
    if [[ $tags == *(in|unless)=* ]]; then
      for tag in ${(s:,:)tags}; do
        [[ $tag == in=* ]] && dir=${tag#in=}
        if [[ $tag == unless=* ]]; then
          # suppress the hint when the suggested tool is already present:
          # a command in PATH, a shell function, or an alias (e.g. zoxide
          # wrapping cd means typing cd IS using zoxide — nothing to teach)
          u=${tag#unless=}
          (( $+commands[$u] || $+functions[$u] || $+aliases[$u] )) && { skip=1; break }
        fi
      done
    fi
    (( skip )) && continue
    _psst_guard_level "$tags" "$hint"
    guard=$REPLY
    rec="${id}"$'\x1f'"${cooldown:-0}"$'\x1f'"${chance:-100}"$'\x1f'"${snooze:-0}"$'\x1f'"${dir}"$'\x1f'"${guard}"$'\x1f'"${hint}"
    case $kind in
      cmd)
        for t in ${(s:,:)targets}; do
          [[ -z $t ]] && continue
          if [[ -n ${_psst_cmd_map[$t]} ]]; then
            _psst_cmd_map[$t]+=$'\x1e'"$rec"
          else
            _psst_cmd_map[$t]=$rec
          fi
        done
        ;;
      pat) _psst_pat_list+=("${targets}"$'\x1f'"$rec") ;;
      any) _psst_any_list+=("$rec") ;;
    esac
  done < "$PSST_HINTS"
  return 0
}

# Words that precede the real command; flags after these are skipped too.
typeset -gA _psst_precmds
_psst_precmds=(sudo 1 doas 1 command 1 builtin 1 exec 1 nocorrect 1 noglob 1 nice 1 time 1 env 1 nohup 1 stdbuf 1)

# Tiny LCG so the hot path never touches the user's $RANDOM (whose seed we
# must not disturb, and which freezes inside subshells). Reseeded from the
# clock on every hook invocation.
typeset -g _psst_seed=1
_psst_rand() { # <n> — sets REPLY to 0..n-1
  (( _psst_seed = (_psst_seed * 1103515245 + 12345) & 0x7fffffff ))
  REPLY=$(( _psst_seed % $1 ))
}

# _psst_cmd_word <line> — sets REPLY to the resolved command word (basename), "" if none
_psst_cmd_word() {
  emulate -L zsh
  setopt extended_glob
  REPLY=""
  local -a words
  words=(${(z)1})
  local w guard=0
  while (( $#words && guard++ < 12 )); do
    w=$words[1]
    if [[ $w == [A-Za-z_][A-Za-z0-9_]#=* ]]; then           # env assignment prefix
      words=("${(@)words[2,-1]}")
    elif [[ -n ${_psst_precmds[$w]} ]]; then                 # precommand modifier
      words=("${(@)words[2,-1]}")
      while (( $#words )) && [[ $words[1] == -* ]]; do       # skip its flags
        words=("${(@)words[2,-1]}")
      done
    else
      break
    fi
  done
  (( $#words )) && REPLY="${words[1]:t}"
  return 0
}

# _psst_effective_word <typed> <expanded> — sets REPLY to the command the user
# is really running. If the typed name is an alias that redirects to a
# DIFFERENT command (alias cat='bat'), the target wins — the user already
# upgraded, so hints registered on the typed name are suppressed.
_psst_effective_word() {
  local tw="" ew=""
  _psst_cmd_word "$1"; tw=$REPLY
  if [[ -n $2 && $2 != "$1" ]]; then
    _psst_cmd_word "$2"; ew=$REPLY
  fi
  if [[ -n $ew && -n $tw && $ew != "$tw" ]]; then
    REPLY=$ew
  else
    REPLY=${tw:-$ew}
  fi
  return 0
}

# _psst_match <typed> <expanded> [effective-word]
# Fills $reply with matching records (deduped by id). Does NOT filter by
# cooldown/chance/snooze — callers decide (the hook filters, `psst try` shows all).
_psst_match() {
  emulate -L zsh
  setopt extended_glob
  local typed=$1 expanded=$2 w=$3 REPLY
  [[ $expanded == "$typed" ]] && expanded=""
  reply=()
  local -A seen
  local rec pat entry
  if [[ -z $w ]]; then
    _psst_effective_word "$typed" "$expanded"
    w=$REPLY
  fi
  if [[ -n $w && -n ${_psst_cmd_map[$w]} ]]; then
    for rec in "${(@ps:\x1e:)_psst_cmd_map[$w]}"; do
      [[ -n ${seen[${rec%%$'\x1f'*}]} ]] && continue
      seen[${rec%%$'\x1f'*}]=1
      reply+=("$rec")
    done
  fi
  for entry in "${_psst_pat_list[@]}"; do
    pat=${entry%%$'\x1f'*}
    rec=${entry#*$'\x1f'}
    if [[ $typed == ${~pat} ]] || [[ -n $expanded && $expanded == ${~pat} ]]; then
      [[ -n ${seen[${rec%%$'\x1f'*}]} ]] && continue
      seen[${rec%%$'\x1f'*}]=1
      reply+=("$rec")
    fi
  done
  for rec in "${_psst_any_list[@]}"; do
    [[ -n ${seen[${rec%%$'\x1f'*}]} ]] && continue
    seen[${rec%%$'\x1f'*}]=1
    reply+=("$rec")
  done
  return 0
}

# _psst_emit <hint-text> [level] — print one styled hint line to stderr.
# warn → yellow with a ⚠️ badge; danger → red with ❗⚠️. The badge replaces a
# leading ⚠️/❗ in the text so it never doubles up.
_psst_emit() {
  local level=${2:--}
  local reset=$'\e[0m'
  local style body icon prefix=${PSST_PREFIX:-psst} btext=$1
  case $level in
    danger)
      style=${PSST_DANGER_STYLE:-$'\e[1;38;5;196m'}
      body=${PSST_DANGER_BODY_STYLE:-$'\e[0;38;5;196m'}
      icon="❗⚠️"
      btext=${btext#❗ }; btext=${btext#⚠️ }
      ;;
    warn)
      style=${PSST_WARN_STYLE:-$'\e[1;38;5;220m'}
      body=${PSST_WARN_BODY_STYLE:-$'\e[0;38;5;220m'}
      icon="⚠️"
      btext=${btext#⚠️ }
      ;;
    *)
      style=${PSST_STYLE:-$'\e[1;38;5;213m'}
      body=${PSST_BODY_STYLE:-$'\e[0;38;5;213m'}
      icon=${PSST_ICON:-💡}
      ;;
  esac
  print -r -- "${style}${icon} ${prefix}${reset}${body} · ${btext}${reset}" >&2
}

# _psst_guard <level> — live "Are you sure?" countdown on stderr.
# Enter → run now · Esc/Ctrl+C → cancel · timeout → auto-continue.
# Sets _psst_guard_result to proceed|cancel. Never fails.
_psst_guard() {
  emulate -L zsh
  setopt localtraps
  local level=$1 secs style label reset=$'\e[0m'
  if [[ $level == danger ]]; then
    secs=${PSST_GUARD_DANGER:-60}
    style=$'\e[1;38;5;196m'
    label="❗ ARE YOU SURE?"
  else
    secs=${PSST_GUARD_WARN:-30}
    style=$'\e[1;38;5;220m'
    label="⏳ Are you sure?"
  fi
  [[ $secs == <-> ]] || secs=30
  _psst_guard_result=proceed
  trap '_psst_guard_result=cancel' INT
  # a real terminal needs read -k's raw-mode handling (canonical mode would
  # buffer until Enter); a pipe (tests) needs an explicit -u 0
  local -a rdopts
  [[ -t 0 ]] || rdopts=(-u 0)
  local key left
  for (( left = secs; left > 0; left-- )); do
    print -rn -- $'\r\e[K'"${style}   ${label}${reset} auto-runs in ${style}${left}s${reset} ${PSST_DIM:-$'\e[2m'}· Enter = run now · Esc/Ctrl+C = cancel${reset} " >&2
    key=""
    read -s -t 1 -k 1 $rdopts key 2>/dev/null
    [[ $_psst_guard_result == cancel ]] && break
    case $key in
      ($'\r'|$'\n') break ;;
      ($'\e'|$'\x03') _psst_guard_result=cancel; break ;;
    esac
  done
  # drain queued bytes (e.g. the [A of an arrow key) so nothing leaks to zle
  while read -s -t 0 -k 1 $rdopts key 2>/dev/null; do :; done
  print -rn -- $'\r\e[K' >&2
  [[ $_psst_guard_result == cancel ]] && \
    print -r -- $'\e[1;32m'"✋ psst · cancelled — command not run${reset}" >&2
  return 0
}

# _psst_pause_maybe <base> <now> — after a hint fires, hold the command for a
# beat so the hint gets read before output scrolls it away. Applies ONCE per
# base command per day (persisted across sessions in
# $PSST_STATE_DIR/paused.tsv), resets daily. Duration resolution:
# $PSST_PAUSE (session) > $PSST_DIR/pause file (global CLI toggle) > 1s.
_psst_pause_maybe() {
  emulate -L zsh
  local base=${1:--} now=$2
  local pause=${PSST_PAUSE:-}
  if [[ -z $pause ]]; then
    if [[ -r $PSST_DIR/pause ]]; then pause=$(<$PSST_DIR/pause); else pause=1; fi
  fi
  [[ $pause == (<->|<->.<->|.<->) ]] || pause=1
  (( pause > 0 )) || return 0

  # sync today's already-paused set (mtime-gated, shared across sessions)
  local pfile="$PSST_STATE_DIR/paused.tsv" today psig="missing"
  strftime -s today '%Y-%m-%d' $now 2>/dev/null || today=$(( now / 86400 ))
  local -A pst
  zstat -H pst -- "$pfile" 2>/dev/null && psig="${pst[mtime]}:${pst[size]}:${pst[inode]}"
  if [[ $psig != "$_psst_paused_sig" || $today != "$_psst_paused_day" ]]; then
    _psst_paused=()
    _psst_paused_day=$today
    _psst_paused_sig=$psig
    if [[ $psig != missing ]]; then
      local d c
      while IFS=$'\t' read -r d c || [[ -n $d ]]; do
        [[ $d == "$today" ]] && _psst_paused[$c]=1
      done < "$pfile"
    fi
  fi
  [[ -n ${_psst_paused[$base]} ]] && return 0

  _psst_paused[$base]=1
  if [[ ! -d $PSST_STATE_DIR ]]; then
    zf_mkdir -p "$PSST_STATE_DIR" 2>/dev/null || command mkdir -p "$PSST_STATE_DIR" 2>/dev/null
  fi
  print -r -- "${today}"$'\t'"${base}" 2>/dev/null >> "$pfile"
  local -i cs=$(( pause * 100 ))
  if (( cs > 0 )); then
    if (( $+builtins[zselect] )); then
      zselect -t $cs
    else
      command sleep $pause
    fi
  fi
  return 0
}

# The preexec hook. Receives (typed, single-line-expanded, full-expanded).
# Must never fail, never block, never touch the command.
_psst_preexec() {
  emulate -L zsh
  setopt extended_glob
  {
    [[ -n $PSST_QUIET ]] && return 0
    [[ -t 2 || -n $PSST_FORCE ]] || return 0
    [[ -e $PSST_DIR/off ]] && return 0
    local REPLY
    _psst_file_sig
    [[ $REPLY != "$_psst_sig" ]] && _psst_load
    [[ $_psst_sig == missing ]] && return 0
    (( ${#_psst_cmd_map} + ${#_psst_pat_list} + ${#_psst_any_list} )) || return 0

    # per-command mute: `psst hide <cmd>` silences EVERYTHING for that base
    # command — cmd hints, pattern hints, any-hints (mtime-gated file sync)
    local base=""
    _psst_effective_word "$1" "$3"
    base=$REPLY
    if [[ -n $base ]]; then
      local hsig="missing"
      local -A hst
      zstat -H hst -- "$PSST_DIR/hidden" 2>/dev/null && hsig="${hst[mtime]}:${hst[size]}:${hst[inode]}"
      if [[ $hsig != "$_psst_hidden_sig" ]]; then
        _psst_hidden_sig=$hsig
        _psst_hidden_load
      fi
      [[ -n ${_psst_hidden[$base]} ]] && return 0
    fi

    local -a reply
    _psst_match "$1" "$3" "$base"
    (( $#reply )) || return 0

    local now=$EPOCHSECONDS
    (( now - _psst_last_any < ${PSST_MIN_GAP:-0} )) && return 0
    # reseed from the clock's sub-second digits (base-10 forced: they can
    # start with 0 and must not parse as octal)
    (( _psst_seed = (_psst_seed ^ (now + 10#${${EPOCHREALTIME#*.}[1,9]})) & 0x7fffffff ))

    local -a live f
    local rec
    for rec in "${reply[@]}"; do
      f=("${(@ps:\x1f:)rec}")   # id cooldown chance until dir guard hint
      (( f[4] > now )) && continue                                              # snoozed
      (( f[2] > 0 && now - ${_psst_last_shown[$f[1]]:-0} < f[2] )) && continue  # cooldown
      if [[ $f[5] != - ]]; then                                                 # dir-scoped
        [[ $PWD == ${~f[5]}* || ${PWD:A} == ${~f[5]}* ]] || continue
      fi
      if (( f[3] < 100 )); then                                                 # chance
        _psst_rand 100
        (( REPLY >= f[3] )) && continue
      fi
      live+=("$rec")
    done
    (( $#live )) || return 0

    _psst_rand $#live
    rec=$live[$(( REPLY + 1 ))]
    f=("${(@ps:\x1f:)rec}")
    _psst_emit "$f[7]" "$f[6]"
    _psst_last_shown[$f[1]]=$now
    _psst_last_any=$now
    if [[ ${PSST_STATS:-1} == 1 ]]; then
      if [[ ! -d $PSST_STATE_DIR ]]; then
        zf_mkdir -p "$PSST_STATE_DIR" 2>/dev/null || command mkdir -p "$PSST_STATE_DIR" 2>/dev/null
      fi
      print -r -- "${EPOCHSECONDS}"$'\t'"$f[1]" 2>/dev/null >> "$PSST_STATE_DIR/shown.log"
    fi
    if [[ $f[6] != - && ${PSST_GUARD:-1} != 0 && ! -e $PSST_DIR/guard-off ]] \
       && { [[ -t 0 && -t 2 ]] || [[ -n $PSST_GUARD_FORCE ]] }; then
      _psst_guard "$f[6]"
      if [[ $_psst_guard_result == cancel ]]; then
        # abort the pending command: an interrupt during preexec makes zsh
        # drop the command line and return to the prompt (pty-verified)
        [[ -n $PSST_GUARD_NO_KILL ]] || kill -INT $$
        return 0
      fi
    else
      _psst_pause_maybe "$base" $now
    fi
  } always {
    return 0
  }
}
