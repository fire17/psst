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
zmodload zsh/datetime 2>/dev/null

typeset -gA _psst_cmd_map     # command name -> $'\x1e'-joined records
typeset -ga _psst_pat_list    # "pattern \x1f record" entries
typeset -ga _psst_any_list    # records
typeset -gA _psst_last_shown  # hint id -> epoch last shown (this session)
typeset -g  _psst_sig=""      # mtime:size:inode signature of the loaded hints file
typeset -g  _psst_last_any=0  # epoch any hint was last shown (global gap)

# _psst_file_sig — sets REPLY to the hints file signature ("missing" if unreadable)
_psst_file_sig() {
  local -A st
  if zstat -H st -- "$PSST_HINTS" 2>/dev/null; then
    REPLY="${st[mtime]}:${st[size]}:${st[inode]}"
  else
    REPLY="missing"
  fi
}

# record layout, $'\x1f'-separated: id cooldown chance until dir hint
_psst_load() {
  emulate -L zsh
  _psst_cmd_map=() _psst_pat_list=() _psst_any_list=()
  local REPLY
  _psst_file_sig
  _psst_sig=$REPLY
  [[ $_psst_sig == missing ]] && return 0
  local id on kind targets cooldown chance snooze tags hint
  local rec t dir tag
  while IFS=$'\t' read -r id on kind targets cooldown chance snooze tags hint || [[ -n $id ]]; do
    [[ -z $id || $id == \#* ]] && continue
    [[ $on == 1 ]] || continue
    dir="-"
    if [[ $tags == *in=* ]]; then
      for tag in ${(s:,:)tags}; do
        [[ $tag == in=* ]] && dir=${tag#in=}
      done
    fi
    rec="${id}"$'\x1f'"${cooldown:-0}"$'\x1f'"${chance:-100}"$'\x1f'"${snooze:-0}"$'\x1f'"${dir}"$'\x1f'"${hint}"
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

# _psst_match <typed> <expanded>
# Fills $reply with matching records (deduped by id). Does NOT filter by
# cooldown/chance/snooze — callers decide (the hook filters, `psst try` shows all).
_psst_match() {
  emulate -L zsh
  setopt extended_glob
  local typed=$1 expanded=$2 REPLY
  [[ $expanded == "$typed" ]] && expanded=""
  reply=()
  local -A seen
  local line rec pat entry
  for line in "$typed" "$expanded"; do
    [[ -z $line ]] && continue
    _psst_cmd_word "$line"
    [[ -z $REPLY ]] && continue
    if [[ -n ${_psst_cmd_map[$REPLY]} ]]; then
      for rec in "${(@ps:\x1e:)_psst_cmd_map[$REPLY]}"; do
        [[ -n ${seen[${rec%%$'\x1f'*}]} ]] && continue
        seen[${rec%%$'\x1f'*}]=1
        reply+=("$rec")
      done
    fi
  done
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

# _psst_emit <hint-text> — print one styled hint line to stderr
_psst_emit() {
  local style=${PSST_STYLE:-$'\e[1;38;5;213m'}
  local body=${PSST_BODY_STYLE:-$'\e[0;38;5;213m'}
  local icon=${PSST_ICON:-💡}
  local prefix=${PSST_PREFIX:-psst}
  local reset=$'\e[0m'
  print -r -- "${style}${icon} ${prefix}${reset}${body} · ${1}${reset}" >&2
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

    local -a reply
    _psst_match "$1" "$3"
    (( $#reply )) || return 0

    local now=$EPOCHSECONDS
    (( now - _psst_last_any < ${PSST_MIN_GAP:-0} )) && return 0
    # reseed from the clock's sub-second digits (base-10 forced: they can
    # start with 0 and must not parse as octal)
    (( _psst_seed = (_psst_seed ^ (now + 10#${${EPOCHREALTIME#*.}[1,9]})) & 0x7fffffff ))

    local -a live f
    local rec
    for rec in "${reply[@]}"; do
      f=("${(@ps:\x1f:)rec}")   # id cooldown chance until dir hint
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
    _psst_emit "$f[6]"
    _psst_last_shown[$f[1]]=$now
    _psst_last_any=$now
    if [[ ${PSST_STATS:-1} == 1 ]]; then
      if [[ ! -d $PSST_STATE_DIR ]]; then
        zf_mkdir -p "$PSST_STATE_DIR" 2>/dev/null || command mkdir -p "$PSST_STATE_DIR" 2>/dev/null
      fi
      print -r -- "${EPOCHSECONDS}"$'\t'"$f[1]" 2>/dev/null >> "$PSST_STATE_DIR/shown.log"
    fi
  } always {
    return 0
  }
}
