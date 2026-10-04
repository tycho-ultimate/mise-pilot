# Instructions for AI agents

(`AGENTS.md` is a symlink to this file.) This project was made from `tycho-ultimate/project-template`. These are
its conventions; the owner may add project-specific ones below them.

## Before you commit

1. `tests/script-agent.sh`, the project's own tests, and
   `mise exec shellcheck@0.11.0 -- shellcheck script/agent tests/*.sh` all pass. CI (`.github/workflows/ci.yml`)
   runs the same, plus `script/agent doctor`, and must be green before a merge.
2. Changed behaviour? Add or update a test. Fixed a bug? Add a test that fails without the fix.
3. Work on a branch and open a PR to `main`; the owner merges. Never push `main`, force-push, delete a branch or
   merge.

## The stack is declared in `mise.toml`

- Every language and tool the project needs goes under `[tools]` in `mise.toml`, as an exact version
  (`python = "3.13.7"`), never `latest` or a fuzzy prefix. Then `mise install`, `mise lock`, and commit
  `mise.toml` and `mise.lock` together.
- The agent accounts, your machine and CI all install from that one file. Never install a language some other way
  (a `setup-*` action in CI, a curl-pipe installer, a system package) and never ask for `sudo`. Anything that needs
  root belongs in the machine's image, not in this repo.
- `mise.toml` stays in the safe subset: `min_version` and plain versions under `[tools]`. These load without
  `mise trust` and run no repo code.
- **Not without the owner's approval**, in a PR the owner authors: `[env]` (including `_.source`, `_.file` and
  `_.path`), `exec()` or `read_file()` templates, `[hooks]`, a tool's `postinstall` or `install_env`, `[tasks]`,
  `[plugins]`, `asdf:` or `vfox:` tools, `include`, `[settings]`, `mise.<env>.toml` and `conf.d/`. Each one runs
  code or changes the environment when mise loads the file or installs a tool, and crew's doctor flags them.
- `min_version` is at or below the mise version CI pins (`version:` in `ci.yml`); raise the two together.

## `script/agent` is crew's entry point

- The contract is tycho-ultimate/crew's BRIEF D3: the verbs `doctor` and `session <task>` (and `verify <task>`
  for a verifier, not provided yet); exit codes 0, 64 (bad task or usage), 69 (missing prerequisite), 75 (retry
  later), 77 (forbidden); the non-secret environment `CREW_API=1`, `CREW_PROJECT`, `CREW_ROLE`, `CREW_MACHINE`,
  `CREW_TASK`.
- It runs only inside the project's agent account or CI, never as the owner. POSIX sh, shellcheck-clean.
- Never `sudo`, never a secret (it reads its own credentials inside the account, if it ever needs any), and no
  free text in argv: only validated names, such as the task id after its charset check.
- `start_session` is the one place a project changes what a session runs. Keep `tests/script-agent.sh` passing.
- A PR that changes `script/agent` is a protected change in crew's sense: say so in the PR.

## Protected paths

`CLAUDE.md`, `AGENTS.md`, `.claude/**` and `.github/**` change only in PRs the owner authors; the owner's own
Claude sessions count. An unattended agent never edits them: it writes a "Proposed CLAUDE.md change" (or workflow
change) section in its PR body, and an owner session applies it.

## CI

- Every action is pinned by its full commit SHA, with its tag in a comment beside it.
- `permissions: contents: read` unless a job needs more, and then only for that job.
- No secret in CI, in the repo, in a log or on a command line. This repo may be public.
