@AGENTS.md

# Claude Code-specific instructions

- `AGENTS.md` is the canonical source for shared project instructions.
- Do not duplicate shared project rules in this file.
- When project-wide instructions need updating, update `AGENTS.md`.

# Tooling differences from Codex

`AGENTS.md` describes XcodeBuildMCP because Codex has that MCP server configured
(`~/.codex/config.toml` → `mcp_servers.XcodeBuildMCP`). Claude Code does not.
Use `xcodebuild` and `xcrun simctl` through `Bash` instead. The "Build & Run" and
"Testing" sections of `AGENTS.md` give the CLI equivalents.

Claude Code does have the iOS Simulator MCP, and it works here. See
`AGENTS.md` → "Simulator".

# Codex delegation

Models, effort and launch rules live in `~/.claude/CLAUDE.md` and apply here.

`scripts/codex-agent.sh` runs one bounded slice in an isolated git worktree
(`.worktrees/<slice>`, branch `codex/<slice>`, output in `.codex-runs/`). Use it
only when two or more slices would collide on edits. A single slice runs with
`codex exec` in the current checkout.

```bash
scripts/codex-agent.sh <slice> <plan.md>                 # gpt-6.1-sol, medium
scripts/codex-agent.sh <slice> <plan.md> --effort low
scripts/codex-agent.sh <slice> --cleanup
```

Its runs cannot `git commit`: the worktree's `index.lock` lives in the main
repo's `.git/worktrees/`, outside Codex's workspace-write sandbox. Put "leave
changes uncommitted" in every spec, then review and commit the worktree yourself.
Android E2E (adb, emulators, Gradle) works inside that sandbox.
`.claude/settings.json` allowlists the script for unattended runs.
