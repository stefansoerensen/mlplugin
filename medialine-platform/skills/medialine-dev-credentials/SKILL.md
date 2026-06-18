---
name: medialine-dev-credentials
description: How to mint, install, rotate, and revoke per-developer credentials for the Medialine platform (MCP servers, Gitea, Jenkins). Every dev needs three tokens; tasktool mints them for you.
---

# Medialine developer credentials

Every Medialine developer has three platform tokens, all minted by tasktool on your behalf:

| Token | Used by | Env var |
|---|---|---|
| **MCP bearer** (`mlmcp_…`) | Claude Code → MCP servers (diag, plugin, registry, ext-api) | `MEDIALINE_MCP_TOKEN` |
| **Gitea PAT** (`mlgitea_…`) | Claude Code → mcp-gitea; raw git clone/push | `MEDIALINE_GITEA_PAT` |
| **Jenkins token** (`mljenkins_…`) | Claude Code → mcp-jenkins; raw Jenkins API calls | `MEDIALINE_JENKINS_TOKEN` |

Tasktool stores only the sha256 hash of each token. Plaintext is shown ONCE at mint time. The Gitea and Jenkins tokens are also created in the respective upstream systems (admin-mediated) so revocation cascades.

## One-time setup

1. **Get promoted to developer** — an admin sets your `role` to `developer` in `/admin/users`. The moment they save, tasktool auto-mints all three tokens for you. They appear on `/dev/me/credentials` with name `auto-provision`.

2. **Copy the plaintexts** — refresh the page; the plaintexts are shown ONCE in the green banner per kind. Click "Copy" on each.

3. **Persist them as env vars on your machine**:

   **Windows (PowerShell, persistent for your user)**:
   ```powershell
   [Environment]::SetEnvironmentVariable("MEDIALINE_MCP_TOKEN",     "mlmcp_…",     "User")
   [Environment]::SetEnvironmentVariable("MEDIALINE_GITEA_PAT",     "mlgitea_…",   "User")
   [Environment]::SetEnvironmentVariable("MEDIALINE_JENKINS_TOKEN", "mljenkins_…", "User")
   ```

   **macOS / Linux** — append to `~/.zshrc` or `~/.bashrc`:
   ```sh
   export MEDIALINE_MCP_TOKEN="mlmcp_…"
   export MEDIALINE_GITEA_PAT="mlgitea_…"
   export MEDIALINE_JENKINS_TOKEN="mljenkins_…"
   ```

4. **Restart your terminal / VSCode** so the new env vars are inherited. Reload the VSCode window once.

5. **Verify** — open `/dev/me/verify` (Phase 2 page). Three green checkmarks for the three tokens, plus reachability checks for the 6 MCP servers.

## Rotating

- Mint a new one from `/dev/me/credentials`.
- Swap the env var, restart terminal, reload VSCode.
- Revoke the old one (trash icon).
- Revocation takes effect within ~60 s (validate-result cache TTL).

## Where each token is checked

- **MCP bearer**: every `/mcp` request to `https://tasktool.medialine.com/mcp/<slug>/mcp` carries it. mcp-servers' `BearerAuthMiddleware` calls `tasktool /api/dev-credentials/validate`. Cache 60 s.
- **Gitea PAT**: same path for mcp-gitea (once a future PR sets `MCP_AUTH_REQUIRE_KIND=gitea_pat`); also usable for raw git CLI (`git config http.extraheader "Authorization: Bearer mlgitea_…"`).
- **Jenkins token**: same for mcp-jenkins; also usable for raw Jenkins API (`curl -u admin:mljenkins_…`).

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `/mcp` shows server as failed; logs show `401 missing_or_invalid_authorization_header` | env var not set in the shell that launched Claude Code |
| `401 invalid_or_revoked_token` | token revoked or never minted — check `/dev/me/credentials` |
| `403 wrong_token_kind` | wrong kind sent to a server that requires a specific kind (e.g., mcp_bearer sent to mcp-gitea after it's been tightened) |
| All 6 servers fail simultaneously | tasktool-backend down OR `platform.dev_credentials` table missing — check `/api/health` |
| Token works for tasktool MCPs but git push still asks for password | env var alone isn't enough for raw git CLI — also set the git extraheader (see above) |

## Security model

- **Trust boundary**: tasktool's `/api/dev-credentials/validate`. The MCP containers trust the middleware; the raw Gitea/Jenkins APIs trust their respective tokens.
- **Hashing**: only sha256 hash stored. Plaintext is shown once at mint time and cannot be recovered.
- **No expiry**: tokens are long-lived; rotation is explicit. `last_used_at` lets you see stale tokens to revoke.
- **Service-account-mediated**: tasktool acts as Gitea/Jenkins admin to mint your sub-tokens. The push/build action is technically by `admin` in those systems, but tasktool's audit log records you as the trigger, and mcp-gitea sets the commit *author* to your real name (so `git log` shows you).

## Related skills
- [[medialine-platform-services]] — overall service map
- [[diag-api]] — using your MCP bearer to read prod logs through mcp-diag
