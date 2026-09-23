#!/usr/bin/env bash
# Scan mcpServers, enabled plugins, and standalone tool deps (rtk) and report
# what's missing on this device. Run standalone or via install.sh.
set -euo pipefail

SETTINGS="${1:-$HOME/.claude/settings.json}"
CLAUDE_JSON="${2:-$HOME/.claude.json}"
PLUGINS_DIR="${3:-$HOME/.claude/plugins}"
command -v jq >/dev/null 2>&1 || { echo "missing required tool: jq" >&2; exit 1; }

hint() {
    case "$1" in
        npx)  echo "install Node.js (includes npx): https://nodejs.org" ;;
        uvx)  echo "install uv (includes uvx): curl -LsSf https://astral.sh/uv/install.sh | sh" ;;
        node) echo "install Node.js: https://nodejs.org" ;;
        *)    echo "install '$1' and ensure it's on PATH" ;;
    esac
}

missing=0
seen=""
while IFS=$'\t' read -r name cmd; do
    cmd="${cmd%$'\r'}"
    case " $seen " in *" $name "*) continue ;; esac
    seen="$seen $name"
    [ -z "$cmd" ] || [ "$cmd" = "null" ] && continue
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "OK      $name -> $cmd"
    else
        echo "MISSING $name -> $cmd  ($(hint "$cmd"))"
        missing=$((missing + 1))
    fi
done < <(
    for f in "$CLAUDE_JSON" "$SETTINGS"; do
        [ -f "$f" ] && jq -r '.mcpServers // {} | to_entries[] | [.key, (.value.command // "")] | @tsv' "$f"
    done
)

echo
echo "--- plugins ---"
if [ -f "$SETTINGS" ]; then
    while IFS=$'\t' read -r plugin_id; do
        plugin_id="${plugin_id%$'\r'}"
        marketplace="${plugin_id#*@}"
        cache_root="$PLUGINS_DIR/cache"
        if [ -n "$(find "$cache_root" -maxdepth 3 -ipath "*${marketplace}*" 2>/dev/null | head -n1)" ]; then
            echo "OK      $plugin_id (cached)"
        else
            echo "MISSING $plugin_id  (not cached yet: run 'claude plugin install $plugin_id' or let Claude Code fetch it on next start)"
            missing=$((missing + 1))
        fi
    done < <(jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' "$SETTINGS")
fi

echo
echo "--- other tools ---"
if command -v rtk >/dev/null 2>&1; then
    echo "OK      rtk -> $(command -v rtk)"
else
    echo "MISSING rtk  (install: https://github.com/rtk-ai/rtk)"
    missing=$((missing + 1))
fi

if [ "$missing" -gt 0 ]; then
    echo
    echo "$missing item(s) missing." >&2
    exit 1
fi
echo
echo "all MCP servers, plugins, and tools available."
