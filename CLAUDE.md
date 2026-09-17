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

## Model and effort

Same policy as the `parta` repo:

- Delegate with `gpt-5.6-luna` at `max` reasoning effort. This is the default.
- Use `gpt-5.6-sol` at `medium` or `high` only after Luna fails one verification
  cycle. Do not use `gpt-5.6-terra`.
- Always name the effort when you name the model. `codex exec` has no `--effort`
  flag; pass `-c model_reasoning_effort=<level>` and confirm the
  `reasoning effort:` line in the run banner. This repo has no `.codex/config.toml`,
  so an unspecified run inherits `gpt-5.6-sol` + `medium` from `~/.codex/config.toml`.
- Do not enable the Codex review gate. It can put Claude and Codex in a loop.

## Reading a dead thread

Codex rollouts live in `~/.codex/sessions/<YYYY>/<MM>/<DD>/rollout-*-<thread-id>.jsonl`.
When the user hands over a `codex://threads/<id>` link, find that file and parse
it — it contains the original request, every tool call, and where the run died.
This is how an interrupted Codex run gets picked up rather than restarted.
