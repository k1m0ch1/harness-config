#!/usr/bin/env bash
# Import this Claude Code + CCS + cliproxy setup onto a new device.
# Public config comes from this repo; real secrets are pulled from the
# private companion repo k1m0ch1/harness-config-secrets via `gh` (already
# authenticated `gh auth login` required).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_REPO="k1m0ch1/harness-config-secrets"
TS="$(date +%Y%m%d%H%M%S)"

for bin in git gh jq; do
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

backup "$HOME/.claude"
backup "$HOME/.ccs"

mkdir -p "$HOME/.claude" "$HOME/.ccs"
cp -a "$SCRIPT_DIR/claude/." "$HOME/.claude/"
cp -a "$SCRIPT_DIR/ccs/." "$HOME/.ccs/"

TMP_SECRETS="$(mktemp -d)"
trap 'rm -rf "$TMP_SECRETS"' EXIT
gh repo clone "$SECRETS_REPO" "$TMP_SECRETS" -- -q

# whole-file secrets, overwriting the sanitized public copies where they overlap
cp -a "$TMP_SECRETS/claude/.credentials.json" "$HOME/.claude/.credentials.json" 2>/dev/null || true
cp -a "$TMP_SECRETS/ccs/.session-secret" "$HOME/.ccs/.session-secret" 2>/dev/null || true
for f in "$TMP_SECRETS"/ccs/*.settings.json; do
    [ -e "$f" ] && cp -a "$f" "$HOME/.ccs/$(basename "$f")"
done
[ -d "$TMP_SECRETS/ccs/cliproxy" ] && cp -a "$TMP_SECRETS/ccs/cliproxy" "$HOME/.ccs/"
[ -d "$TMP_SECRETS/ccs/proxy" ] && mkdir -p "$HOME/.ccs/proxy" && cp -a "$TMP_SECRETS/ccs/proxy/." "$HOME/.ccs/proxy/"

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

find "$HOME/.claude/.credentials.json" "$HOME/.ccs/.session-secret" "$HOME/.ccs/cliproxy" "$HOME/.ccs/proxy" \
    -type f -exec chmod 600 {} + 2>/dev/null || true

echo "done. Backups (if any) are at ~/.claude.bak.$TS and ~/.ccs.bak.$TS"

bash "$SCRIPT_DIR/scripts/check-mcp.sh" "$HOME/.claude/settings.json" || true
