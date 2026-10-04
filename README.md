# project-template

Template for new tycho-ultimate projects: `mise.toml`, `script/agent`, and CI with mise.

Make a project from it:

```sh
gh repo create tycho-ultimate/<name> --template tycho-ultimate/project-template --public
```

Then replace this README with the project's own, and keep the sections below that still apply.

## How this project gets its stack

1. **The repo declares it.** `mise.toml` lists every language and tool, at exact versions. `mise.lock` records
   where each one is downloaded from and its checksum.
2. **The agent account's mise installs it.** In the account, in the clone: `mise install`. That runs inside the
   agent account, never as the owner, and needs no root. `script/agent doctor` says which declared tools are
   installed.
3. **CI does the same.** `.github/workflows/ci.yml` installs mise (a pinned version) with `jdx/mise-action`, which
   runs `mise install` from the same file, with `--locked` once `mise.lock` exists.

Your own machine works the same way: install mise, then `mise install` in the clone.

### Add a tool

```sh
# 1. Add a line under [tools] in mise.toml, at an exact version:
#      python = "3.13.7"
mise install        # 2. install it here
mise lock           # 3. write or update mise.lock (versions, URLs, checksums)
git add mise.toml mise.lock
```

The template declares no tool yet, so it has no `mise.lock`: `mise lock` writes one once `[tools]` lists a tool.
Keep `mise.toml` to `min_version` and plain versions under `[tools]` (see `CLAUDE.md` for what needs the
owner's approval, and why).

## `script/agent`

crew's entry point (tycho-ultimate/crew, BRIEF D3). It runs inside the project's agent account.

| Command | What it does |
|---|---|
| `script/agent doctor` | Checks git, mise, and that every tool in `mise.toml` is installed. Exits 0, or 69 when something is missing. |
| `script/agent session <task>` | Checks the task id and the `CREW_*` environment, takes a per-task lock in the clone, then runs `start_session`: by default the account's login shell, with the tools on PATH. |

Exit codes: 0 ok, 64 bad task id or usage, 69 missing prerequisite, 75 retry later (the task is already in a
session in this clone), 77 forbidden (a session as root, or for the verifier role).

Change `start_session` to launch your agent. `tests/script-agent.sh` checks the contract offline, with fakes.

## Files

```
mise.toml                  the stack: min_version and [tools]
script/agent               crew's entry point (POSIX sh)
tests/script-agent.sh      script/agent's contract, offline
.github/workflows/ci.yml   mise install, shellcheck, tests, script/agent doctor
CLAUDE.md                  conventions for agents (AGENTS.md is a symlink to it)
```
