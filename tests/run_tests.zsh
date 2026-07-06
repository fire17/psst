#!/usr/bin/env zsh
# psst test suite — sandboxed, never touches real user data.
emulate -R zsh
setopt extended_glob

ROOT=${0:A:h:h}
CLI=$ROOT/bin/psst

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/psst-tests.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT
export PSST_DIR=$SANDBOX/config
export PSST_HINTS=$PSST_DIR/hints.tsv
export PSST_STATE_DIR=$SANDBOX/state
export PSST_FORCE=1          # bypass tty check — tests capture stderr
export NO_COLOR=1
export PSST_PAUSE=0          # keep tests instant; pause has its own timed section
unset PSST_QUIET PSST_MIN_GAP PSST_STYLE PSST_ICON PSST_PREFIX

source "$ROOT/lib/core.zsh"

typeset -g PASS=0 FAIL=0
pass() { (( PASS++ )); print -r -- "  ✓ $1" }
fail() { (( FAIL++ )); print -r -- "  ✗ $1"; [[ -n $2 ]] && print -r -- "      got: $2" }

assert_contains() { # name haystack needle
  if [[ $2 == *$3* ]]; then pass "$1"; else fail "$1" "$2"; fi
}
assert_empty() { # name value
  if [[ -z $2 ]]; then pass "$1"; else fail "$1" "$2"; fi
}
assert_eq() { # name got want
  if [[ $2 == $3 ]]; then pass "$1"; else fail "$1" "got '$2', want '$3'"; fi
}

# run the hook against a typed (and optionally expanded) line, capture the hint
hook() { # typed [expanded]
  _psst_load
  _psst_preexec "$1" "" "${2:-$1}" 2>&1
}

reset_store() {
  command rm -rf "$PSST_DIR" "$PSST_STATE_DIR"
  _psst_last_shown=() _psst_last_any=0 _psst_sig=""
}

print "— add & match —"
reset_store
"$CLI" add nano "Use fresh for a more modern file editor! :D" >/dev/null
out=$(hook "nano notes.txt")
assert_contains "cmd hint fires on nano" "$out" "Use fresh"
out=$(hook "nanoX notes.txt")
assert_empty "no fire on similar-but-different command" "$out"
out=$(hook "ls -la")
assert_empty "no fire on unrelated command" "$out"
out=$("$CLI" list)
assert_contains "list shows the hint" "$out" "Use fresh"

print "— seamless: args, paths, prefixes, aliases —"
out=$(hook "nano -w 'my file with spaces.txt' --restricted")
assert_contains "fires with quoted/odd args" "$out" "Use fresh"
out=$(hook "/usr/bin/nano x")
assert_contains "fires on absolute path" "$out" "Use fresh"
out=$(hook "sudo nano /etc/hosts")
assert_contains "fires behind sudo" "$out" "Use fresh"
out=$(hook "sudo -E nano /etc/hosts")
assert_contains "fires behind sudo with flags" "$out" "Use fresh"
out=$(hook "EDITOR=vi LANG=C nano x")
assert_contains "fires behind env assignments" "$out" "Use fresh"
out=$(hook "n x" "nano x")
assert_contains "fires via alias expansion" "$out" "Use fresh"
rc=0; _psst_preexec "nano x" "" "nano x" >/dev/null 2>&1 || rc=$?
assert_eq "hook always returns 0" "$rc" "0"

print "— multi-target & multi-hint —"
reset_store
"$CLI" add nano,pico,vi "editors hint" >/dev/null
out=$(hook "pico a b c")
assert_contains "comma targets: pico" "$out" "editors hint"
out=$(hook "vi .zshrc")
assert_contains "comma targets: vi" "$out" "editors hint"
"$CLI" add nano "second nano hint" >/dev/null
saw1=0 saw2=0
for i in {1..40}; do
  out=$(hook "nano f")
  [[ $out == *"editors hint"* ]] && saw1=1
  [[ $out == *"second nano hint"* ]] && saw2=1
  (( saw1 && saw2 )) && break
done
assert_eq "multiple hints rotate randomly" "$saw1$saw2" "11"

print "— patterns —"
reset_store
"$CLI" add --pat 'git push *(-f|--force)(| *)' "use --force-with-lease" >/dev/null
out=$(hook "git push --force")
assert_contains "pattern: --force" "$out" "force-with-lease"
out=$(hook "git push -f")
assert_contains "pattern: -f" "$out" "force-with-lease"
out=$(hook "git push origin main -f")
assert_contains "pattern: -f with args" "$out" "force-with-lease"
out=$(hook "git push origin my-feature")
assert_empty "pattern: no false positive on my-feature" "$out"
out=$(hook "git push --force-with-lease")
assert_empty "pattern: no fire when already doing it right" "$out"

print "— any-command hints —"
reset_store
"$CLI" add --any "drink water 💧" >/dev/null
out=$(hook "whatever-command --with args")
assert_contains "any-hint fires on any command" "$out" "drink water"

print "— cooldown / snooze / chance / dir —"
reset_store
addout=$("$CLI" add --cooldown 1h nano "cooldown hint")
id=${${(s: :)${addout#*added }}[1]}
out=$( { _psst_load
         _psst_preexec "nano a" "" "nano a"
         _psst_preexec "nano a" "" "nano a" } 2>&1 )
typeset -a outlines; outlines=("${(@f)out}")
cnt=${#${(M)outlines:#*cooldown hint*}}
assert_eq "cooldown: fires once, then suppressed" "$cnt" "1"
out=$(hook "nano a")
assert_contains "cooldown: first fire (fresh session)" "$out" "cooldown hint"
"$CLI" snooze "$id" 1h >/dev/null
_psst_last_shown=()
out=$(hook "nano a")
assert_empty "snoozed hint is silent" "$out"
"$CLI" wake "$id" >/dev/null
out=$(hook "nano a")
assert_contains "woken hint fires again" "$out" "cooldown hint"

reset_store
"$CLI" add --chance 1 nano "rare hint" >/dev/null
hits=0
for i in {1..200}; do
  out=$(hook "nano f")
  [[ -n $out ]] && (( hits++ ))
done
if (( hits < 60 )); then pass "chance 1% is rare ($hits/200)"; else fail "chance 1% fired too often" "$hits/200"; fi

reset_store
"$CLI" add --in "$SANDBOX" nano "dir-scoped hint" >/dev/null
out=$(cd "$SANDBOX" && hook "nano f")
assert_contains "dir-scoped: fires inside" "$out" "dir-scoped"
out=$(cd / && hook "nano f")
assert_empty "dir-scoped: silent outside" "$out"

print "— on/off/toggle/done/rm —"
reset_store
addout=$("$CLI" add nano "toggle me")
id=${${(s: :)${addout#*added }}[1]}
"$CLI" off >/dev/null
out=$(hook "nano f")
assert_empty "global off silences" "$out"
"$CLI" on >/dev/null
out=$(hook "nano f")
assert_contains "global on restores" "$out" "toggle me"
"$CLI" toggle "$id" >/dev/null
out=$(hook "nano f")
assert_empty "per-hint toggle off" "$out"
"$CLI" toggle "$id" >/dev/null
out=$(hook "nano f")
assert_contains "per-hint toggle on" "$out" "toggle me"
"$CLI" done "$id" >/dev/null
out=$(hook "nano f")
assert_empty "done = learned = silent" "$out"
out=$("$CLI" list --porcelain)
assert_contains "done keeps row with learned tag" "$out" "learned"
"$CLI" rm "$id" >/dev/null
out=$("$CLI" list --porcelain)
assert_empty "rm removes row" "$out"

print "— session env toggles —"
reset_store
"$CLI" add nano "quiet test" >/dev/null
out=$(PSST_QUIET=1 hook "nano f")
assert_empty "PSST_QUIET silences" "$out"
_psst_last_any=$EPOCHSECONDS
out=$(PSST_MIN_GAP=9999 hook "nano f")
assert_empty "PSST_MIN_GAP throttles" "$out"
_psst_last_any=0

print "— packs —"
reset_store
"$CLI" pack install modern-unix >/dev/null
out=$(hook "cat file.txt")
assert_contains "pack hint fires (cat→bat)" "$out" "bat"
out=$("$CLI" pack install modern-unix)
assert_contains "reinstall skips duplicates" "$out" "already present"
"$CLI" pack remove modern-unix >/dev/null
out=$(hook "cat file.txt")
assert_empty "pack remove silences" "$out"

print "— import/export —"
reset_store
"$CLI" add nano "hint A" >/dev/null
"$CLI" add --pat 'git log' "hint B" >/dev/null
"$CLI" export "$SANDBOX/backup.tsv" >/dev/null
"$CLI" rm --all >/dev/null
out=$("$CLI" list --porcelain)
assert_empty "rm --all empties store" "$out"
"$CLI" import "$SANDBOX/backup.tsv" >/dev/null
out=$("$CLI" list --porcelain)
assert_contains "import restores hint A" "$out" "hint A"
assert_contains "import restores hint B" "$out" "hint B"

print "— try / stats / doctor / robustness —"
reset_store
"$CLI" add nano "try me" >/dev/null
out=$("$CLI" try nano config.txt)
assert_contains "try reports matching hint" "$out" "try me"
hook "nano f" >/dev/null
out=$("$CLI" stats)
assert_contains "stats counts a fire" "$out" "try me"
print -r -- $'garbage line without tabs' >> "$PSST_HINTS"
out=$(hook "nano f")
assert_contains "hook survives malformed row" "$out" "try me"
out=$("$CLI" doctor); rc=$?
assert_contains "doctor flags malformed row" "$out" "✗"
out=$(reset_store; hook "nano f")
assert_empty "hook is silent with no store at all" "$out"

print "— unless: skip hints for tools already present —"
reset_store
"$CLI" add --unless zsh cat "redundant hint" >/dev/null        # zsh is certainly present
out=$(hook "cat f")
assert_empty "unless=<installed tool> suppresses" "$out"
reset_store
"$CLI" add --unless not-a-real-tool-xyz cat "useful hint" >/dev/null
out=$(hook "cat f")
assert_contains "unless=<missing tool> fires" "$out" "useful hint"
reset_store
"$CLI" pack install modern-unix >/dev/null
out=$("$CLI" list --porcelain)
assert_contains "pack carries unless tag (zoxide)" "$out" "unless=zoxide"

print "— alias-redirect suppression (already upgraded) —"
reset_store
"$CLI" add cat "use bat!" >/dev/null
out=$(hook "cat f" "bat f")                    # alias cat='bat'
assert_empty "typed name aliased to different cmd: suppressed" "$out"
out=$(hook "cat f" "cat --color=auto f")       # alias to same cmd with flags
assert_contains "alias to same command still fires" "$out" "use bat!"
"$CLI" add bat "bat power tips exist" >/dev/null
out=$(hook "cat f" "bat f")
assert_contains "target command's own hints fire through the alias" "$out" "bat power"

print "— hide/show per command —"
reset_store
"$CLI" add nano "hidden test hint" >/dev/null
"$CLI" hide nano >/dev/null
out=$(hook "nano f")
assert_empty "hidden command is silent" "$out"
out=$(hook "n f" "nano f")
assert_empty "hidden via alias too" "$out"
out=$("$CLI" hide)
assert_contains "bare hide lists hidden commands" "$out" "nano"
out=$("$CLI" try nano f)
assert_contains "try warns about hidden command" "$out" "hidden"
"$CLI" show nano >/dev/null
out=$(hook "nano f")
assert_contains "show unmutes the command" "$out" "hidden test hint"
"$CLI" add --pat 'git push *(-f|--force)(| *)' "lease hint" >/dev/null
"$CLI" add --any "any hint here" >/dev/null
"$CLI" hide git >/dev/null
out=$(hook "git push -f")
assert_empty "hide suppresses pattern & any hints for that command" "$out"
"$CLI" show git >/dev/null
addout=$("$CLI" add vim "vim detail hint")
vid=${${(s: :)${addout#*added }}[1]}
out=$("$CLI" show $vid)
assert_contains "show <id> still prints hint details" "$out" "vim detail hint"

print "— list table & command-scoped verbs —"
reset_store
"$CLI" add nano "first nano hint" >/dev/null
"$CLI" add nano "second nano hint" >/dev/null
"$CLI" add --any "any tip" >/dev/null
"$CLI" hide nano >/dev/null
out=$("$CLI" list)
assert_contains "table shows the command" "$out" "nano"
assert_contains "table shows example hint" "$out" "first nano hint"
assert_contains "table shows (any) bucket" "$out" "(any)"
assert_contains "table marks hidden commands" "$out" "(hidden)"
"$CLI" show nano >/dev/null
out=$("$CLI" nano list)
assert_contains "scoped list is numbered" "$out" " 1"
assert_contains "scoped list shows all hints" "$out" "second nano hint"
"$CLI" nano add "third via scope" >/dev/null
out=$("$CLI" nano list)
assert_contains "psst <cmd> add works" "$out" "third via scope"
"$CLI" nano rm 2 >/dev/null
out=$("$CLI" nano list)
if [[ $out == *"second nano hint"* ]]; then
  fail "psst <cmd> rm <n> removed the wrong hint" "$out"
else
  pass "psst <cmd> rm <n> removes the n-th hint"
fi
assert_contains "other hints survive scoped rm" "$out" "first nano hint"
out=$("$CLI" any list)
assert_contains "psst any list manages --any hints" "$out" "any tip"
out=$("$CLI" nosuchcmd list)
assert_contains "unknown base command explains itself" "$out" "no hints"
out=$("$CLI" nano hide && "$CLI" nano list)
assert_contains "psst <cmd> hide works" "$out" "hidden"
"$CLI" nano show >/dev/null
out=$("$CLI" list --full)
assert_contains "flat view still available via --full" "$out" "first nano hint"

print "— pause: breather once per command per day —"
reset_store
"$CLI" add pausecmd,othercmd,stalecmd "read me first" >/dev/null
typeset -F pt0 pt1
pt0=$EPOCHREALTIME; out=$(PSST_PAUSE=1 hook "pausecmd a"); pt1=$EPOCHREALTIME
assert_contains "hint shows with pause enabled" "$out" "read me first"
if (( pt1 - pt0 >= 0.9 )); then pass "first run pauses ~1s"; else fail "first run did not pause" "$(( pt1 - pt0 ))s"; fi
pt0=$EPOCHREALTIME; out=$(PSST_PAUSE=1 hook "pausecmd b"); pt1=$EPOCHREALTIME
assert_contains "hint still shows on later runs" "$out" "read me first"
if (( pt1 - pt0 < 0.6 )); then pass "same command: no second pause today"; else fail "paused again for same command" "$(( pt1 - pt0 ))s"; fi
pt0=$EPOCHREALTIME; out=$(PSST_PAUSE=1 hook "pc x" "pausecmd x"); pt1=$EPOCHREALTIME
if (( pt1 - pt0 < 0.6 )); then pass "alias of already-paused command: no pause"; else fail "alias re-paused" "$(( pt1 - pt0 ))s"; fi
pt0=$EPOCHREALTIME; out=$(PSST_PAUSE=1 hook "othercmd x"); pt1=$EPOCHREALTIME
if (( pt1 - pt0 >= 0.9 )); then pass "different command pauses"; else fail "different command did not pause" "$(( pt1 - pt0 ))s"; fi
assert_contains "paused state persisted to disk" "$(<$PSST_STATE_DIR/paused.tsv)" "pausecmd"
print -r -- $'2020-01-01\tstalecmd' > "$PSST_STATE_DIR/paused.tsv"
pt0=$EPOCHREALTIME; out=$(PSST_PAUSE=1 hook "stalecmd x"); pt1=$EPOCHREALTIME
if (( pt1 - pt0 >= 0.9 )); then pass "old-day entries reset daily"; else fail "stale entry suppressed today's pause" "$(( pt1 - pt0 ))s"; fi
command rm -f "$PSST_STATE_DIR/paused.tsv"
pt0=$EPOCHREALTIME; out=$(PSST_PAUSE=0 hook "othercmd x"); pt1=$EPOCHREALTIME
if (( pt1 - pt0 < 0.5 )); then pass "PSST_PAUSE=0 disables pause"; else fail "paused despite PSST_PAUSE=0" "$(( pt1 - pt0 ))s"; fi
"$CLI" pause off >/dev/null
command rm -f "$PSST_STATE_DIR/paused.tsv"
pt0=$EPOCHREALTIME; out=$(unset PSST_PAUSE; hook "othercmd x"); pt1=$EPOCHREALTIME
if (( pt1 - pt0 < 0.5 )); then pass "psst pause off disables globally"; else fail "paused despite pause off" "$(( pt1 - pt0 ))s"; fi
"$CLI" pause on >/dev/null
command rm -f "$PSST_STATE_DIR/paused.tsv"
pt0=$EPOCHREALTIME; out=$(unset PSST_PAUSE; hook "othercmd x"); pt1=$EPOCHREALTIME
if (( pt1 - pt0 >= 0.9 )); then pass "psst pause on restores globally"; else fail "no pause after pause on" "$(( pt1 - pt0 ))s"; fi
out=$("$CLI" pause status)
assert_contains "pause status reports on" "$out" "on"
"$CLI" pause 0.5 >/dev/null
out=$("$CLI" pause status)
assert_contains "pause accepts custom seconds" "$out" "0.5"
"$CLI" pause off >/dev/null
out=$("$CLI" pause status)
assert_contains "pause status reports off" "$out" "off"

print "— performance (hot path) —"
reset_store
"$CLI" add nano "perf hint" >/dev/null
"$CLI" pack install modern-unix git safety >/dev/null
_psst_load
typeset -F t0=$EPOCHREALTIME
for i in {1..300}; do
  _psst_preexec "nano file-$i.txt" "" "nano file-$i.txt" 2>/dev/null
done
typeset -F t1=$EPOCHREALTIME
typeset -F 2 ms_per=$(( (t1 - t0) * 1000 / 300 ))
if (( (t1 - t0) * 1000 / 300 < 3 )); then
  pass "hot path avg ${ms_per}ms per command (< 3ms)"
else
  fail "hot path too slow" "${ms_per}ms per command"
fi

print
if (( FAIL )); then
  print -r -- "✗ $FAIL failed, $PASS passed"
  exit 1
else
  print -r -- "✓ all $PASS tests passed"
fi
