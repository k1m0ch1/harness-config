# harness-config

Portable export of a Claude Code + [CCS](https://github.com/kaitranntt/ccs) +
cliproxy setup, so a new device can be brought up with one command.

This repo is **public** and holds no real secrets — see [SECRETS.md](SECRETS.md).
Real credential values live in the private companion repo
`k1m0ch1/harness-config-secrets`, pulled in at install time via an
already-authenticated `gh` CLI.

## Layout
- `claude/` → mirrors `~/.claude` (settings, plugins, commands, agents, skills, statusline)
- `ccs/` → mirrors `~/.ccs` (config.yaml, per-provider `*.settings.json` templates, mcp/, launcher `.cmd`s)
- `scripts/export.py` → regenerates both this repo and the private secrets repo from live `~/.claude` + `~/.ccs` state (run on the source machine)
- `install.sh` → imports everything onto a new device
- `flake.nix` → same install, invoked as `nix run github:k1m0ch1/harness-config` if you happen to have nix

## Install on a new device

No nix required — just needs `git`, `gh` (authenticated: `gh auth login`), and `jq`:

```bash
git clone https://github.com/k1m0ch1/harness-config.git
cd harness-config
./install.sh
```

With nix:

```bash
nix run github:k1m0ch1/harness-config
```

Either way it:
1. Backs up any existing `~/.claude` and `~/.ccs` (never overwrites silently).
2. Copies this repo's `claude/` and `ccs/` trees into place.
3. Clones `k1m0ch1/harness-config-secrets` and splices the real tokens/credentials back in.
4. `chmod 600`s everything that came from the secrets repo.

## Re-exporting after making changes on the source machine

```bash
python3 scripts/export.py
```

Re-derives both `harness-config/` and `harness-config-secrets/` from the
current `~/.claude` + `~/.ccs`. Review the diff, then commit/push each repo
separately.
