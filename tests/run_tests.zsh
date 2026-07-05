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
