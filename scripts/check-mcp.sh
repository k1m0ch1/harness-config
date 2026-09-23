#!/usr/bin/env bash
# Scan ~/.claude/settings.json's mcpServers and report whether each server's
# launcher command is installed. Run standalone or via install.sh.
set -euo pipefail

SETTINGS="${1:-$HOME/.claude/settings.json}"
[ -f "$SETTINGS" ] || { echo "not found: $SETTINGS" >&2; exit 1; }
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
while IFS=$'\t' read -r name cmd; do
    cmd="${cmd%$'\r'}"
    [ -z "$cmd" ] || [ "$cmd" = "null" ] && continue
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "OK      $name -> $cmd"
    else
        echo "MISSING $name -> $cmd  ($(hint "$cmd"))"
        missing=$((missing + 1))
    fi
done < <(jq -r '.mcpServers // {} | to_entries[] | [.key, (.value.command // "")] | @tsv' "$SETTINGS")

if [ "$missing" -gt 0 ]; then
    echo "$missing MCP server(s) missing their launcher command." >&2
    exit 1
fi
echo "all MCP server commands available."
