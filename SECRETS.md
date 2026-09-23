# Secret manifest

This repo is public and contains **no real credential values**. Every place a
secret is needed, the public config has a `${SECRET:...}` placeholder or the
whole file is simply missing here. `install.sh` fills these in from the
private companion repo `k1m0ch1/harness-config-secrets`.

## `claude/settings.json` (`mcpServers.*.env` / `.headers`)
- `mcpServers.playwright-extension.env.PLAYWRIGHT_MCP_EXTENSION_TOKEN`
- `mcpServers.gitnexus.headers.X-Api-Key`
- `mcpServers.mem0.env.MEM0_PASSWORD`

Real values live in `harness-config-secrets/claude/claude-settings-secrets.json`.

## `ccs/*.settings.json` (`env.ANTHROPIC_AUTH_TOKEN` etc.)
- `codex.settings.json`, `deepseek.settings.json`, `glm.settings.json`,
  `glm-imam.settings.json`, `glm-k1m0ch1.settings.json`, `kimi.settings.json`,
  `minimax.settings.json`, `openrouter-kantor.settings.json` (`ANTHROPIC_AUTH_TOKEN`
  and, for openrouter-kantor, also `ANTHROPIC_API_KEY`)
- `gemini.settings.json` — no secret fields.

Real, unsanitized copies of every `*.settings.json` file live whole in
`harness-config-secrets/ccs/`.

## `claude/mcpServers.json` (exported from `~/.claude.json`, not `settings.json`)
- `mcpServers.playwright-extension.env.PLAYWRIGHT_MCP_EXTENSION_TOKEN`
- `mcpServers.gitnexus.headers.X-Api-Key`
- `mcpServers.mem0.env.MEM0_PASSWORD`
- `mcpServers.shodan.env.SHODAN_API_KEY`

Real values live in `harness-config-secrets/claude/mcpServers-secrets.json`.
`~/.claude.json`'s top-level `mcpServers` is Claude Code's live MCP registry
(separate from `~/.claude/settings.json`'s `mcpServers` key) — `install.sh`
merges this template into it so servers are available immediately.

## `ccs/config.yaml`
- `TAVILY_API_KEY`

Real value lives in `harness-config-secrets/ccs/config-secrets.json`.

## Files that exist only in the private repo (no public counterpart at all)
- `claude/.credentials.json` — Claude Code OAuth login
- `ccs/.session-secret`
- `ccs/cliproxy/config.yaml`, `accounts.json`, `sessions.json`, `auth/*.json`
- `ccs/proxy/*.session.json`
- `ssh/` — whole `~/.ssh` directory (private keys, `config*`, `known_hosts*`).
  Restored with `chmod 600` on keys / `644` on `*.pub` / `700` on the dir.

## Regenerating this manifest
Run `scripts/export.py` on the source machine — it re-derives both trees
(and this list) from live `~/.claude` + `~/.ccs` state.
