@AGENTS.md

# Claude Code-specific instructions

- `AGENTS.md` is the canonical source for shared project instructions.
- Do not duplicate shared project rules in this file.
- When project-wide instructions need updating, update `AGENTS.md`.

# Tooling differences from Codex

`AGENTS.md` describes XcodeBuildMCP because Codex has that MCP server configured
(`~/.codex/config.toml` → `mcp_servers.XcodeBuildMCP`). **Claude Code does not.**
In this session, use `xcodebuild` and `xcrun simctl` through `Bash` instead. The
"Build & Run" and "Testing" sections of `AGENTS.md` give the CLI equivalents.

The Claude Code iOS Simulator MCP does not work on this Mac either — see
`AGENTS.md` → "Simulator (headless)". Use `xcrun simctl io <udid> screenshot`
for visual checks; do not tell the user to run `sudo xcode-select -s`, and do not
plan verification around a simulator window.

# Codex delegation

Codex reads `AGENTS.md`. Codex does not read this file. These rules apply to
Claude Code only, so they stay here.

## Launching a Codex thread

The `codex@openai-codex` plugin is installed at user scope. Everything runs
through `node "${CLAUDE_PLUGIN_ROOT}/scripts/codex-companion.mjs"`; prefer the
slash commands over calling the script by hand.

| Command | Use |
|---------|-----|
| `/codex:rescue [flags] <task>` | Hand a substantial implementation or root-cause task to Codex. Forwards to the `codex:codex-rescue` subagent. |
| `/codex:transfer` | Turn the *current* Claude session into a resumable Codex thread; returns a session id + `codex resume <id>`. |
| `/codex:status [job-id]` | Active and recent Codex jobs for this repo. |
| `/codex:result <job-id>` | Stored final output of a finished job. |
| `/codex:cancel <job-id>` | Kill an active background job. |
| `/codex:review` / `/codex:adversarial-review` | Review-only passes over local git state. |

`rescue` flags: `--background` / `--wait` (Claude-side execution mode),
`--resume` / `--fresh` (thread routing), `--model <name|spark>`,
`--effort <none…xhigh>`. Long or open-ended work goes `--background`; a small
bounded fix goes `--wait`.

- Invoke the subagent with the `Agent` tool and `subagent_type: "codex:codex-rescue"`.
  There is no `Skill(codex:codex-rescue)`, and `Skill(codex:rescue)` re-enters the
  slash command and hangs the session.
- Return Codex's output verbatim. The rescue subagent is a forwarder — don't have
  it read the repo, poll status, or summarize.

## Parallel fan-out

`scripts/codex-agent.sh` runs one bounded slice in an isolated git worktree
(`.worktrees/<slice>`, branch `codex/<slice>`, output in `.codex-runs/`). Use it
only when two or more slices would otherwise collide on edits; a single slice
belongs in `/codex:rescue`, which works in the current checkout.

```bash
scripts/codex-agent.sh plus docs/superpowers/plans/010-unpaged-plus.md
scripts/codex-agent.sh abs  docs/superpowers/plans/020-audiobookshelf.md --model gpt-6-sol --effort medium
scripts/codex-agent.sh plus --cleanup
```

The script names the model and effort on every `codex exec`, so nothing is
inherited implicitly. `.claude/settings.json` allowlists it for unattended runs.

## Model and effort

Same policy as the `parta` repo:

- Delegate with `gpt-6-luna` at `max` reasoning effort. This is the default.
- Use `gpt-6-sol` at `medium` or `high` for harder tasks, or after Luna fails one
  verification cycle. Do not use `gpt-6-terra`.
- Always name the effort when you name the model. `codex exec` has no `--effort`
  flag; pass `-c model_reasoning_effort=<level>` and confirm the
  `reasoning effort:` line in the run banner. `~/.codex/config.toml` sets a single
  global `model_reasoning_effort` that applies to whichever model a run selects,
  so an unnamed effort silently inherits it. `.codex/config.toml` here
  deliberately pins nothing; `scripts/codex-agent.sh` is the guard.
- Do not enable the Codex review gate. It can put Claude and Codex in a loop.

## If `codex` is not on PATH

`~/.local/bin/codex` symlinks into the binary bundled with ChatGPT.app. App
updates relocate it — it moved from `Contents/Resources/codex` to
`Contents/Resources/codex-cli/bin/codex` — which leaves a dead symlink that
looks like Codex was uninstalled. Repoint it rather than reinstalling:

```bash
ln -sfn /Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex ~/.local/bin/codex
```

The `codex@openai-codex` plugin spawns bare `codex` and treats `ENOENT` as
missing, with no app-bundle fallback, so the symlink is load-bearing.

## Reading a dead thread

Codex rollouts live in `~/.codex/sessions/<YYYY>/<MM>/<DD>/rollout-*-<thread-id>.jsonl`.
When the user hands over a `codex://threads/<id>` link, find that file and parse
it — it contains the original request, every tool call, and where the run died.
This is how an interrupted Codex run gets picked up rather than restarted.
