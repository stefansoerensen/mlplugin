---
name: medialine-mcp-tokens
description: How to mint and use the per-developer bearer token that authenticates Claude Code to the Medialine MCP servers (mcp-diag, mcp-gitea, mcp-jenkins, mcp-registry, mcp-ext-api, mcp-plugin).
---

# Medialine MCP tokens

The 6 Medialine MCP servers are exposed at `https://tasktool.medialine.com/mcp/<slug>/mcp` and require `Authorization: Bearer <token>` on every call. Tokens are minted per developer (or per machine) in the TaskTool admin UI.

## One-time setup

1. **Mint a token**
   - Log in to TaskTool as admin.
   - Open `/admin/mcp-tokens`.
   - Click **Mint token**, pick yourself as the user, enter a name (e.g. `stefan-laptop`, `ci-runner`).
   - **Copy the `mlmcp_…` plaintext** that appears — it is shown ONCE; closing the banner discards it.

2. **Expose it to Claude Code**
   - Set the env var `MEDIALINE_MCP_TOKEN` in the shell that launches Claude Code:
     - macOS/Linux: append to `~/.zshrc` or `~/.bashrc`:
       ```sh
       export MEDIALINE_MCP_TOKEN="mlmcp_…"
       ```
     - Windows (PowerShell, per-user, persistent):
       ```powershell
       [Environment]::SetEnvironmentVariable("MEDIALINE_MCP_TOKEN", "mlmcp_…", "User")
       ```
   - Restart the terminal so the new env var is picked up.

3. **Install / reload the plugin**
   - `/plugin install medialine-platform@^1.2.0`
     (or `/plugin marketplace update medialine` if already installed)
   - `/mcp` should list 6 `medialine-…` servers as connected. If they show `failed`, recheck the env var.

## Rotating

- Mint a new token, switch the env var, restart the terminal.
- Revoke the old one via the trash icon at `/admin/mcp-tokens`.
- Revocation takes effect within ~60 seconds (validate-result cache TTL).

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `/mcp` shows `medialine-diag: failed`; logs show `401 missing_or_invalid_authorization_header` | `MEDIALINE_MCP_TOKEN` env var not set in the Claude Code launching shell |
| `/mcp` shows `failed`; logs show `401 invalid_or_revoked_token` | token was revoked or never minted — check `/admin/mcp-tokens` |
| `/mcp` shows `connected` but a tool call returns 500 | upstream container issue — check `mcp-<slug>` logs via the `diag-api` skill |
| All 6 servers fail simultaneously | tasktool-backend or its `mcp_tokens` table is down — check `/api/health` |

## Security model

- **Trust boundary**: nginx (subdomain + TLS) + TaskTool's `/api/mcp-auth/validate` (token hash lookup). The MCP containers themselves do not re-validate the request; they trust the middleware. Every tool call is attributable to the user the token was minted for.
- **Hashing**: only the sha256 of the token is stored in `platform.mcp_tokens`. Plaintext is shown once at mint time and cannot be recovered.
- **No expiry**: tokens are long-lived; rotation is explicit via the admin UI. `last_used_at` lets admins see stale tokens to revoke.
