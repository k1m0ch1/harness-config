#!/usr/bin/env bash
# Import this Claude Code + CCS + cliproxy setup onto a new device.
# Public config comes from this repo; real secrets are pulled from the
# private companion repo k1m0ch1/harness-config-secrets via `gh` (already
# authenticated `gh auth login` required).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_REPO="k1m0ch1/harness-config-secrets"
TS="$(date +%Y%m%d%H%M%S)"

for bin in git gh jq curl; do
    command -v "$bin" >/dev/null 2>&1 || { echo "missing required tool: $bin" >&2; exit 1; }
done

gh auth status >/dev/null 2>&1 || {
    echo "gh is not authenticated. Run: gh auth login" >&2
    exit 1
}

backup() {
    local target="$1"
    if [ -e "$target" ]; then
        mv "$target" "${target}.bak.${TS}"
        echo "backed up existing $target -> ${target}.bak.${TS}"
    fi
}

# Fetch the secrets BEFORE backing anything up, and force the clone over HTTPS.
# The backup step below moves ~/.ssh out of the way, so an SSH clone here would
# destroy the very credentials it needs (and on a fresh device they may not exist
# yet). gh supplies its own token for the HTTPS clone, so this works either way.
TMP_SECRETS="$(mktemp -d)"
trap 'rm -rf "$TMP_SECRETS"' EXIT
gh repo clone "$SECRETS_REPO" "$TMP_SECRETS" -- -q \
    --config url."https://github.com/".insteadOf="git@github.com:"

backup "$HOME/.claude"
backup "$HOME/.ccs"
backup "$HOME/.ssh"

mkdir -p "$HOME/.claude" "$HOME/.ccs"
cp -a "$SCRIPT_DIR/claude/." "$HOME/.claude/"
cp -a "$SCRIPT_DIR/ccs/." "$HOME/.ccs/"

# whole-file secrets, overwriting the sanitized public copies where they overlap
cp -a "$TMP_SECRETS/claude/.credentials.json" "$HOME/.claude/.credentials.json" 2>/dev/null || true
cp -a "$TMP_SECRETS/ccs/.session-secret" "$HOME/.ccs/.session-secret" 2>/dev/null || true
for f in "$TMP_SECRETS"/ccs/*.settings.json; do
    [ -e "$f" ] && cp -a "$f" "$HOME/.ccs/$(basename "$f")"
done
[ -d "$TMP_SECRETS/ccs/cliproxy" ] && cp -a "$TMP_SECRETS/ccs/cliproxy" "$HOME/.ccs/"
[ -d "$TMP_SECRETS/ccs/proxy" ] && mkdir -p "$HOME/.ccs/proxy" && cp -a "$TMP_SECRETS/ccs/proxy/." "$HOME/.ccs/proxy/"

# ~/.ssh: entirely private keys/configs, restored whole from the secrets repo
if [ -d "$TMP_SECRETS/ssh" ]; then
    mkdir -p "$HOME/.ssh"
    cp -a "$TMP_SECRETS/ssh/." "$HOME/.ssh/"
    find "$HOME/.ssh" -type f ! -name "*.pub" ! -name "known_hosts*" ! -name "config*" -exec chmod 600 {} +
    find "$HOME/.ssh" -type f -name "*.pub" -exec chmod 644 {} +
    chmod 700 "$HOME/.ssh"
    echo "restored ~/.ssh"
fi

# splice real mcpServers.*.env / .headers secrets back into settings.json
SECRETS_JSON="$TMP_SECRETS/claude/claude-settings-secrets.json"
if [ -f "$SECRETS_JSON" ]; then
    tmp_settings="$(mktemp)"
    jq --slurpfile secrets "$SECRETS_JSON" '
      . as $orig
      | reduce ($secrets[0] | to_entries[]) as $e
          ($orig;
            reduce ($e.value | to_entries[]) as $kv
              (.; setpath(($e.key / ".") + [$kv.key]; $kv.value))
          )
    ' "$HOME/.claude/settings.json" > "$tmp_settings"
    mv "$tmp_settings" "$HOME/.claude/settings.json"
    echo "spliced secrets into ~/.claude/settings.json"
fi

# splice real values back into ~/.ccs/config.yaml's ${SECRET:KEY} placeholders
CONFIG_SECRETS_JSON="$TMP_SECRETS/ccs/config-secrets.json"
if [ -f "$CONFIG_SECRETS_JSON" ] && [ -f "$HOME/.ccs/config.yaml" ]; then
    while IFS=$'\t' read -r key val; do
        placeholder="\${SECRET:${key}}"
        esc_val=$(printf '%s' "$val" | sed 's/[&/\]/\\&/g')
        sed -i "s/\"${placeholder//\$/\\$}\"/\"${esc_val}\"/" "$HOME/.ccs/config.yaml"
    done < <(jq -r 'to_entries[] | [.key, .value] | @tsv' "$CONFIG_SECRETS_JSON")
    echo "spliced secrets into ~/.ccs/config.yaml"
fi

# ~/.claude.json's top-level mcpServers is Claude Code's live MCP registry
# (separate from ~/.claude/settings.json's mcpServers) — merge it in so
# installed MCP servers show up without restarting/re-adding manually.
MCP_TEMPLATE="$HOME/.claude/mcpServers.json"
rm -f "$MCP_TEMPLATE"  # stray copy from the claude/ tree cp above; real target is ~/.claude.json
MCP_TEMPLATE="$SCRIPT_DIR/claude/mcpServers.json"
if [ -f "$MCP_TEMPLATE" ]; then
    CLAUDE_JSON="$HOME/.claude.json"
    [ -f "$CLAUDE_JSON" ] || echo '{}' > "$CLAUDE_JSON"
    tmp_json="$(mktemp)"
    jq --slurpfile new "$MCP_TEMPLATE" '.mcpServers = ((.mcpServers // {}) * $new[0])' "$CLAUDE_JSON" > "$tmp_json"
    mv "$tmp_json" "$CLAUDE_JSON"

    MCP_SECRETS_JSON="$TMP_SECRETS/claude/mcpServers-secrets.json"
    if [ -f "$MCP_SECRETS_JSON" ]; then
        tmp_json="$(mktemp)"
        jq --slurpfile secrets "$MCP_SECRETS_JSON" '
          . as $orig
          | reduce ($secrets[0] | to_entries[]) as $e
              ($orig;
                reduce ($e.value | to_entries[]) as $kv
                  (.; setpath(($e.key / ".") + [$kv.key]; $kv.value))
              )
        ' "$CLAUDE_JSON" > "$tmp_json"
        mv "$tmp_json" "$CLAUDE_JSON"
    fi
    echo "merged mcpServers into ~/.claude.json"
fi

find "$HOME/.claude/.credentials.json" "$HOME/.ccs/.session-secret" "$HOME/.ccs/cliproxy" "$HOME/.ccs/proxy" \
    -type f -exec chmod 600 {} + 2>/dev/null || true

# rtk is a standalone Rust CLI, not an MCP server, so it is not in mcpServers
# and nothing above installs it: it compresses bash output before the agent
# reads it. Delegate to upstream's installer rather than reimplementing the
# download -- it resolves the release, verifies the archive's SHA-256 against
# checksums.txt and refuses to install an unverified binary. Set RTK_VERSION to
# pin (e.g. RTK_VERSION=v0.49.0); unset installs the latest release.
if command -v rtk >/dev/null 2>&1; then
    echo "rtk already installed -> $(command -v rtk)"
else
    echo "installing rtk..."
    if ! curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh \
        | RTK_VERSION="${RTK_VERSION:-}" sh; then
        echo "warning: rtk install failed -- install it manually: https://github.com/rtk-ai/rtk" >&2
    fi
    if ! command -v rtk >/dev/null 2>&1 && [ -x "$HOME/.local/bin/rtk" ]; then
        echo "note: rtk is at ~/.local/bin but not on PATH. Add to your shell profile:" >&2
        echo "      export PATH=\"\$HOME/.local/bin:\$PATH\"" >&2
    fi
fi

echo "done. Backups (if any) are at ~/.claude.bak.$TS and ~/.ccs.bak.$TS"

bash "$SCRIPT_DIR/scripts/check-mcp.sh" "$HOME/.claude/settings.json" || true
