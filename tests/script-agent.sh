#!/bin/sh
# tests/script-agent.sh: script/agent's contract with crew (BRIEF D3 in tycho-ultimate/crew).
#   bad task ids and bad usage exit 64; missing or bad CREW_* variables, mise, or a declared tool exit 69;
#   a task already in a session exits 75; root, and the verifier role asking for a session, exit 77.
# Offline: script/agent runs in a throwaway clone with a short PATH, where mise, id and the login shell are
# fakes that log their calls. Nothing is installed and nothing outside the temp dir is touched.
#
#   tests/script-agent.sh                  script/agent under its own #!/bin/sh
#   AGENT_SH=bash tests/script-agent.sh    script/agent under another shell
set -u
LC_ALL=C
export LC_ALL
unset CREW_API CREW_PROJECT CREW_ROLE CREW_MACHINE CREW_TASK

here=$(cd "$(dirname "$0")/.." && pwd -P) || exit 1
runner=
if [ -n "${AGENT_SH-}" ]; then
  runner=$(command -v "$AGENT_SH") || { echo "AGENT_SH: $AGENT_SH not found" >&2; exit 1; }
fi
T=$(mktemp -d "${TMPDIR:-/tmp}/script-agent-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
trap 'exit 130' INT HUP TERM

# The throwaway clone.
repo=$T/repo
mkdir -p "$repo/script" "$T/home" || exit 1
cp "$here/script/agent" "$repo/script/agent" && cp "$here/mise.toml" "$repo/mise.toml" || exit 1
chmod +x "$repo/script/agent"
git -C "$repo" init -q || exit 1
locks=$(git -C "$repo" rev-parse --absolute-git-dir)/agent-sessions

# The short PATH: the real commands script/agent uses, the fakes, and (in its own dir) the fake mise.
sysbin=$T/sysbin
fakes=$T/fakes
misebin=$T/misebin
mkdir -p "$sysbin" "$fakes" "$misebin"
nogit=$T/nogit
mkdir -p "$nogit"
for c in awk cat dirname git head mkdir rm sed tr; do
  p=$(command -v "$c") || { echo "test needs $c" >&2; exit 1; }
  ln -s "$p" "$sysbin/$c"
  [ "$c" = git ] || ln -s "$p" "$nogit/$c"
done
cat >"$fakes/id" <<'EOF'
#!/bin/sh
printf '%s\n' "id $*" >>"$FAKE_LOG"
[ "${1-}" = -u ] && { echo "${FAKE_UID:-1000}"; exit 0; }
exit 1
EOF
cat >"$misebin/mise" <<'EOF'
#!/bin/sh
printf '%s\n' "mise $*" >>"$FAKE_LOG"
case ${1-} in
  ls)
    if [ -n "${FAKE_MISE_FAIL-}" ]; then echo "mise ERROR Config files in /x/mise.toml are not trusted." >&2; exit 1; fi
    cat "$FAKE_MISE_LS"; exit 0 ;;
  exec) shift; [ "${1-}" = -- ] && shift; exec "$@" ;;
esac
exit 2
EOF
cat >"$fakes/shell" <<'EOF'
#!/bin/sh
printf '%s\n' "shell $* task=${CREW_TASK-}" >>"$FAKE_LOG"
for l in "$FAKE_LOCKS"/*.lock/pid; do [ -f "$l" ] && printf '%s\n' "shell sees a lock" >>"$FAKE_LOG"; done
exit "${FAKE_SHELL_RC:-0}"
EOF
chmod +x "$fakes/id" "$misebin/mise" "$fakes/shell"

# What the fake `mise ls --local --json` answers.
ls_none() { printf '{}\n' >"$T/ls.json"; }
ls_tools() {   # <installed: true|false for the second tool>
  cat >"$T/ls.json" <<EOF
{
  "python": [
    {
      "version": "3.13.7",
      "requested_version": "3.13.7",
      "install_path": "/home/x/.local/share/mise/installs/python/3.13.7",
      "source": {
        "type": "mise.toml",
        "path": "/home/x/src/mise.toml"
      },
      "installed": true,
      "active": true
    }
  ],
  "node": [
    {
      "version": "22.20.0",
      "requested_version": "22.20.0",
      "install_path": "/home/x/.local/share/mise/installs/node/22.20.0",
      "source": {
        "type": "mise.toml",
        "path": "/home/x/src/mise.toml"
      },
      "installed": $1,
      "active": false
    }
  ]
}
EOF
}

# Results go to a file, since many checks run in subshells (to scope their variables).
: >"$T/results"
ok() { echo pass >>"$T/results"; }
bad() {
  echo fail >>"$T/results"
  printf 'FAIL %s\n' "$1"
  [ -s "$T/out" ] && sed 's/^/    | /' "$T/out"
  return 0
}

# agent [args...]: run script/agent in the clone with the short PATH; output in $T/out, log in $T/log.
agent() {
  : >"$T/log"
  (
    cd "$repo" || exit 99
    env PATH="${TEST_PATH:-$fakes:$misebin:$sysbin}" HOME="$T/home" SHELL="$fakes/shell" \
      FAKE_LOG="$T/log" FAKE_MISE_LS="$T/ls.json" FAKE_LOCKS="$locks" \
      ${runner:+"$runner"} ./script/agent "$@"
  ) >"$T/out" 2>&1 </dev/null
}

# expect <exit> <name> [args...]
expect() {
  want=$1 name=$2
  shift 2
  agent "$@"
  got=$?
  if [ "$got" = "$want" ]; then ok; else bad "$name: exit $got, want $want"; fi
}
out_has() { if grep -q -e "$1" "$T/out"; then ok; else bad "$2: the output lacks: $1"; fi; }
out_lacks() { if grep -q -e "$1" "$T/out"; then bad "$2: the output has: $1"; else ok; fi; }
log_has() { if grep -q -e "$1" "$T/log"; then ok; else bad "$2: the log lacks: $1"; fi; }
log_empty() { if [ -s "$T/log" ]; then bad "$1: something ran: $(tr '\n' ';' <"$T/log")"; else ok; fi; }

crew() {
  CREW_API=1 CREW_PROJECT=demo CREW_ROLE=implementer CREW_MACHINE=m1
  export CREW_API CREW_PROJECT CREW_ROLE CREW_MACHINE
}

ls_none

# ── usage ──
expect 64 "no verb"
expect 64 "an unknown verb" frobnicate
expect 0 "help" --help
expect 64 "doctor with an argument" doctor extra
expect 69 "verify is not provided" verify T-1

# ── session: bad task ids exit 64 before anything runs, and are never echoed ──
crew
# The $ and backticks below are literal on purpose: they are what an injection looks like.
# shellcheck disable=SC2016
for id in '' '-x' '.x' '_x' 'a b' 'a;b' 'a/b' '../x' 'a$b' '$(id)' '`id`' 'a|b' 'a&b' "a'b" 'a"b' 'a\b' \
  'x*' 'é' 'ACME-1; rm -rf ~' "$(printf 'a\nb')" "$(printf 'a\tb')" "$(printf 'a\033]52;c;eA==\007')" \
  'A1234567890123456789012345678901234567890123456789012345678901234'; do
  shown=$(printf '%s' "$id" | tr -c 'A-Za-z0-9 ._;-' '?')
  expect 64 "session: bad task id [$shown]" session "$id"
  log_empty "session: bad task id [$shown]"
done
expect 0 "session: a 64-character id is allowed" session A123456789012345678901234567890123456789012345678901234567890123
expect 64 "session: no task" session
expect 64 "session: two tasks" session T-1 T-2
(CREW_TASK="T-2"; export CREW_TASK; expect 64 "session: CREW_TASK differs" session T-1; out_has "differ" "CREW_TASK differs")
expect 64 "session: an injected id" session 'T-1;touch PWNED'
out_lacks "PWNED" "an injected id is not echoed"
if [ -e "$repo/PWNED" ]; then bad "an injected id ran"; else ok; fi

# ── session: missing or bad CREW_* variables exit 69 ──
for v in CREW_API CREW_PROJECT CREW_ROLE CREW_MACHINE; do
  (crew; unset "$v"; expect 69 "session without $v" session T-1; out_has "$v" "session without $v names it"; log_empty "session without $v")
done
(crew; CREW_API=2; expect 69 "session with CREW_API=2" session T-1)
(crew; CREW_PROJECT='demo;id'; expect 69 "session with a bad CREW_PROJECT" session T-1; out_lacks ';id' "a bad CREW_PROJECT is not echoed")
(crew; CREW_MACHINE='-m'; expect 69 "session with a bad CREW_MACHINE" session T-1)
(crew; CREW_ROLE="admin"; expect 69 "session with an unknown CREW_ROLE" session T-1)
(unset CREW_API CREW_PROJECT CREW_ROLE CREW_MACHINE; expect 69 "session with no CREW_* at all" session T-1)

# ── session: forbidden (77) ──
(crew; FAKE_UID=0; export FAKE_UID; expect 77 "session as root" session T-1; out_has "root" "session as root says why")
(crew; CREW_ROLE=verifier; expect 77 "session for the verifier role" session T-1)

# ── session: a good run, the lock, and retry later (75) ──
expect 0 "session: a good run" session T-1
out_has "session: task T-1, project demo, role implementer, machine m1" "session: the ready line"
log_has "^mise exec -- $fakes/shell -i" "session: runs the login shell through mise exec"
log_has "^shell -i task=T-1" "session: CREW_TASK reaches the session"
log_has "shell sees a lock" "session: the lock is held while the session runs"
if [ -e "$locks/T-1.lock" ]; then bad "session: the lock is removed afterwards"; else ok; fi
(crew; CREW_TASK="T-1"; export CREW_TASK; expect 0 "session: CREW_TASK equal to the argument" session T-1)
(FAKE_SHELL_RC=3; export FAKE_SHELL_RC; expect 3 "session: the session's exit code comes back" session T-1)
(TEST_PATH=$fakes:$sysbin; expect 0 "session without mise runs the shell directly" session T-1; log_has "^shell -i task=T-1" "session without mise")

mkdir -p "$locks/T-2.lock" && printf '%s\n' "$$" >"$locks/T-2.lock/pid"
expect 75 "session: the task is in a live session" session T-2
out_has "retry" "session: 75 says retry"
if [ -d "$locks/T-2.lock" ]; then ok; else bad "session: a live lock is left alone"; fi
rm -rf "$locks/T-2.lock"
mkdir -p "$locks/T-3.lock"
expect 75 "session: a lock with no pid yet" session T-3
rm -rf "$locks/T-3.lock"
sh -c 'exit 0' &
dead=$!
wait "$dead"
mkdir -p "$locks/T-4.lock" && printf '%s\n' "$dead" >"$locks/T-4.lock/pid"
expect 0 "session: a stale lock is taken over" session T-4
if [ -e "$locks/T-4.lock" ]; then bad "session: the stale lock is gone afterwards"; else ok; fi

# A missing tool is a note at session start, not a failure (crew decision T4).
ls_tools false
expect 0 "session: a missing tool does not stop it" session T-1
out_has "node 22.20.0: not installed" "session: notes the missing tool"
ls_none

# ── doctor ──
unset CREW_API CREW_PROJECT CREW_ROLE CREW_MACHINE CREW_TASK
expect 0 "doctor without crew and with no tools" doctor
out_has "no tools declared" "doctor: says no tools are declared"
log_has "^mise ls --local --json" "doctor: asks mise for the local config only"
expect 0 "doctor under crew" doctor
crew
expect 0 "doctor with CREW_*" doctor
out_has "project demo, role implementer, machine m1" "doctor: names the project"
(CREW_ROLE=verifier; expect 0 "doctor for the verifier role" doctor)
(CREW_API=2; expect 69 "doctor with CREW_API=2" doctor)
(CREW_PROJECT='x y'; expect 69 "doctor with a bad CREW_PROJECT" doctor)
(CREW_TASK='a;b'; export CREW_TASK; expect 64 "doctor with a bad CREW_TASK" doctor)
FAKE_UID=0 && export FAKE_UID
expect 0 "doctor as root still reports" doctor
unset FAKE_UID

ls_tools true
expect 0 "doctor: every tool installed" doctor
out_has "tool python 3.13.7: installed" "doctor: lists python"
out_has "tool node 22.20.0: installed" "doctor: lists node"
out_has "no mise.lock" "doctor: notes a missing mise.lock"
: >"$repo/mise.lock"
expect 0 "doctor: with mise.lock" doctor
out_lacks "no mise.lock" "doctor: no note with mise.lock"
rm -f "$repo/mise.lock"
ls_tools false
expect 69 "doctor: a tool not installed" doctor
out_has "tool node 22.20.0: not installed" "doctor: names the missing tool"
out_has "mise install" "doctor: gives the step"
ls_none

(FAKE_MISE_FAIL=1; export FAKE_MISE_FAIL; expect 69 "doctor: mise cannot read the config" doctor; out_has "not trusted" "doctor: shows mise's reason")
(TEST_PATH=$fakes:$sysbin; expect 69 "doctor without mise" doctor; out_has "mise: not found" "doctor without mise says so")
(TEST_PATH=$fakes:$misebin:$nogit; expect 69 "doctor without git" doctor; out_has "git: not found" "doctor without git says so")

PASSED=$(grep -c pass "$T/results")
FAILED=$(grep -c fail "$T/results")
total=$((PASSED + FAILED))
if [ "$FAILED" -eq 0 ]; then
  echo "tests/script-agent.sh: all $total checks passed${runner:+ (script/agent under $runner)}"
  exit 0
fi
echo "tests/script-agent.sh: $FAILED of $total checks failed${runner:+ (script/agent under $runner)}"
exit 1
