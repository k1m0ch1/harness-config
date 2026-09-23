#!/usr/bin/env python3
"""One-shot export of live ~/.claude + ~/.ccs into harness-config (public)
and harness-config-secrets (private) trees. Re-run to refresh both."""
import json
import os
import re
import shutil
from pathlib import Path

HOME = Path(os.environ["USERPROFILE"])
PUB = Path(r"C:\Users\k1m0c\harness-work\harness-config")
SEC = Path(r"C:\Users\k1m0c\harness-work\harness-config-secrets")

SECRET_KEY_RE = re.compile(r"(KEY|TOKEN|SECRET|PASSWORD|PASS)", re.IGNORECASE)


YAML_SECRET_LINE_RE = re.compile(
    r"^(?P<indent>\s*)(?P<key>[A-Za-z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD|PASS)[A-Za-z0-9_]*)\s*:\s*(?P<val>\S.*)$"
)


def sanitize_ccs_config_yaml():
    """config.yaml is YAML with comments, not JSON — line-based sanitize:
    any non-comment `SOME_KEY: value` line whose key looks secret-ish gets
    its value replaced with a placeholder and the real value recorded."""
    src = HOME / ".ccs" / "config.yaml"
    if not src.exists():
        print("  MISSING (skipped): ccs/config.yaml")
        return
    lines = src.read_text(encoding="utf-8").splitlines()
    secrets = {}
    out_lines = []
    for line in lines:
        stripped = line.strip()
        m = None if stripped.startswith("#") else YAML_SECRET_LINE_RE.match(line)
        if m and m.group("val").strip('"').strip("'"):
            key = m.group("key")
            secrets[key] = m.group("val")
            out_lines.append(f'{m.group("indent")}{key}: "${{SECRET:{key}}}"')
        else:
            out_lines.append(line)
    dest = PUB / "ccs" / "config.yaml"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text("\n".join(out_lines) + "\n", encoding="utf-8")
    sec_dest = SEC / "ccs" / "config-secrets.json"
    sec_dest.parent.mkdir(parents=True, exist_ok=True)
    sec_dest.write_text(json.dumps(secrets, indent=2) + "\n", encoding="utf-8")
    print(f"ccs/config.yaml -> sanitized ({len(secrets)} secret keys extracted)")


def sanitize_env_block(d: dict, path: str, secrets: dict):
    """Mutate d in place: replace secret-ish values with placeholders,
    recording real values into secrets[path] = {key: value}."""
    out = {}
    for k, v in d.items():
        if isinstance(v, str) and SECRET_KEY_RE.search(k):
            out.setdefault(path, {})[k] = v
            d[k] = f"${{SECRET:{k}}}"
    if out:
        secrets.update(out)


def sanitize_claude_settings():
    src = HOME / ".claude" / "settings.json"
    d = json.loads(src.read_text(encoding="utf-8"))
    secrets = {}
    for name, cfg in d.get("mcpServers", {}).items():
        if isinstance(cfg.get("env"), dict):
            sanitize_env_block(cfg["env"], f"mcpServers.{name}.env", secrets)
        if isinstance(cfg.get("headers"), dict):
            sanitize_env_block(cfg["headers"], f"mcpServers.{name}.headers", secrets)
    dest = PUB / "claude" / "settings.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(d, indent=2) + "\n", encoding="utf-8")
    sec_dest = SEC / "claude" / "claude-settings-secrets.json"
    sec_dest.parent.mkdir(parents=True, exist_ok=True)
    sec_dest.write_text(json.dumps(secrets, indent=2) + "\n", encoding="utf-8")
    print(f"claude/settings.json -> sanitized ({len(secrets)} secret paths extracted)")


def sanitize_claude_json_mcpservers():
    """~/.claude.json's top-level mcpServers is Claude Code's actual live MCP
    registry (settings.json's mcpServers key is a separate/legacy list) —
    export it too so install.sh can restore it."""
    src = HOME / ".claude.json"
    if not src.exists():
        print("  MISSING (skipped): ~/.claude.json")
        return
    d = json.loads(src.read_text(encoding="utf-8"))
    mcp = json.loads(json.dumps(d.get("mcpServers", {})))  # deep copy
    secrets = {}
    for name, cfg in mcp.items():
        if isinstance(cfg.get("env"), dict):
            sanitize_env_block(cfg["env"], f"mcpServers.{name}.env", secrets)
        if isinstance(cfg.get("headers"), dict):
            sanitize_env_block(cfg["headers"], f"mcpServers.{name}.headers", secrets)
    dest = PUB / "claude" / "mcpServers.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(mcp, indent=2) + "\n", encoding="utf-8")
    sec_dest = SEC / "claude" / "mcpServers-secrets.json"
    sec_dest.parent.mkdir(parents=True, exist_ok=True)
    sec_dest.write_text(json.dumps(secrets, indent=2) + "\n", encoding="utf-8")
    print(f"claude.json mcpServers -> sanitized ({len(secrets)} secret paths extracted)")


def sanitize_ccs_settings_files():
    names = [
        "glm.settings.json", "glm-imam.settings.json", "glm-k1m0ch1.settings.json",
        "kimi.settings.json", "deepseek.settings.json", "minimax.settings.json",
        "openrouter-kantor.settings.json", "codex.settings.json", "gemini.settings.json",
    ]
    for name in names:
        src = HOME / ".ccs" / name
        if not src.exists():
            continue
        # whole real file -> secrets repo (source of truth for real tokens)
        sec_dest = SEC / "ccs" / name
        sec_dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, sec_dest)

        # sanitized template -> public repo
        try:
            d = json.loads(src.read_text(encoding="utf-8"))
        except Exception:
            print(f"  skip sanitize (not JSON): {name}")
            continue
        profile = name.replace(".settings.json", "")
        if isinstance(d.get("env"), dict):
            for k, v in list(d["env"].items()):
                if isinstance(v, str) and SECRET_KEY_RE.search(k):
                    d["env"][k] = f"${{SECRET:{profile}:{k}}}"
        pub_dest = PUB / "ccs" / name
        pub_dest.parent.mkdir(parents=True, exist_ok=True)
        pub_dest.write_text(json.dumps(d, indent=2) + "\n", encoding="utf-8")
    print(f"ccs/*.settings.json -> {len(names)} profiles processed")


import hashlib

# sha256 digests (length 11) of known leaked secret substrings found
# embedded in stale settings.local.json permission entries (e.g. a
# hardcoded password inside an old heredoc). Only the digest is stored so
# this sanitizer can live in the public repo without re-leaking the secret
# itself.
BAD_SUBSTRING_LEN = 11
BAD_SUBSTRING_HASHES = {
    "5375d92aad446cfd719fa18282d189b710550b14441ac6072d25606e5086703a",
    "9fed1e27ed54310c2036a2ce096962aa244fe888ff56b8bb8ec0ce6ee7cb06c2",
}


def _contains_bad_substring(s: str) -> bool:
    # substrings can appear anywhere in a long string, so hash every
    # contiguous run of the known secret length
    for i in range(len(s) - BAD_SUBSTRING_LEN + 1):
        chunk = s[i:i + BAD_SUBSTRING_LEN].encode("utf-8", "ignore")
        if hashlib.sha256(chunk).hexdigest() in BAD_SUBSTRING_HASHES:
            return True
    return False


def sanitize_settings_local():
    """settings.local.json is a free-text permission allow/deny/ask list —
    scan for embedded real secrets (not just placeholder defaults) and drop
    any entry that contains one, e.g. a stale heredoc with a hardcoded
    password. This isn't a general secret scanner; it's here because one
    such entry was found and stripped during the first export."""
    src = HOME / ".claude" / "settings.local.json"
    d = json.loads(src.read_text(encoding="utf-8"))
    for bucket in ("allow", "deny", "ask"):
        lst = d.get("permissions", {}).get(bucket, [])
        d["permissions"][bucket] = [
            s for s in lst
            if not (isinstance(s, str) and _contains_bad_substring(s))
        ]
    dest = PUB / "claude" / "settings.local.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(d, indent=2) + "\n", encoding="utf-8")
    print("claude/settings.local.json -> sanitized")


def copy_public_verbatim():
    pairs = [
        (HOME / ".claude" / "plugins" / "installed_plugins.json", PUB / "claude" / "plugins" / "installed_plugins.json"),
        (HOME / ".claude" / "plugins" / "known_marketplaces.json", PUB / "claude" / "plugins" / "known_marketplaces.json"),
        (HOME / ".claude" / "statusline.sh", PUB / "claude" / "statusline.sh"),
        (HOME / ".claude" / "custom-statusline.sh", PUB / "claude" / "custom-statusline.sh"),
    ]
    for src, dest in pairs:
        if not src.exists():
            print(f"  MISSING (skipped): {src}")
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)

    dir_pairs = [
        (HOME / ".claude" / "commands", PUB / "claude" / "commands"),
        (HOME / ".claude" / "agents", PUB / "claude" / "agents"),
        (HOME / ".claude" / "skills", PUB / "claude" / "skills"),
        (HOME / ".ccs" / "mcp", PUB / "ccs" / "mcp"),
    ]
    for src, dest in dir_pairs:
        if not src.exists():
            print(f"  MISSING dir (skipped): {src}")
            continue
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(src, dest)

    # ccs-*.cmd launcher scripts
    ccs_dir = HOME / ".ccs"
    dest_dir = PUB / "ccs"
    dest_dir.mkdir(parents=True, exist_ok=True)
    for f in ccs_dir.glob("ccs-*.cmd"):
        shutil.copy2(f, dest_dir / f.name)
    print("public verbatim files/dirs copied")


def copy_secrets_verbatim():
    pairs = [
        (HOME / ".claude" / ".credentials.json", SEC / "claude" / ".credentials.json"),
        (HOME / ".ccs" / ".session-secret", SEC / "ccs" / ".session-secret"),
        (HOME / ".ccs" / "cliproxy" / "config.yaml", SEC / "ccs" / "cliproxy" / "config.yaml"),
        (HOME / ".ccs" / "cliproxy" / "accounts.json", SEC / "ccs" / "cliproxy" / "accounts.json"),
        (HOME / ".ccs" / "cliproxy" / "sessions.json", SEC / "ccs" / "cliproxy" / "sessions.json"),
    ]
    for src, dest in pairs:
        if not src.exists():
            print(f"  MISSING (skipped): {src}")
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)

    auth_src = HOME / ".ccs" / "cliproxy" / "auth"
    if auth_src.exists():
        auth_dest = SEC / "ccs" / "cliproxy" / "auth"
        if auth_dest.exists():
            shutil.rmtree(auth_dest)
        shutil.copytree(auth_src, auth_dest)

    proxy_src = HOME / ".ccs" / "proxy"
    if proxy_src.exists():
        proxy_dest = SEC / "ccs" / "proxy"
        proxy_dest.mkdir(parents=True, exist_ok=True)
        for f in proxy_src.glob("*.session.json"):
            shutil.copy2(f, proxy_dest / f.name)

    # ~/.ssh is entirely private keys/configs/known_hosts -- whole dir is secret
    ssh_src = HOME / ".ssh"
    if ssh_src.exists():
        ssh_dest = SEC / "ssh"
        if ssh_dest.exists():
            shutil.rmtree(ssh_dest)
        shutil.copytree(ssh_src, ssh_dest)

    print("secret verbatim files/dirs copied")


if __name__ == "__main__":
    sanitize_claude_settings()
    sanitize_claude_json_mcpservers()
    sanitize_settings_local()
    sanitize_ccs_settings_files()
    sanitize_ccs_config_yaml()
    copy_public_verbatim()
    copy_secrets_verbatim()
    print("done")
