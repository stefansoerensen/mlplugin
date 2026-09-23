---
name: medialine-dev-credentials
description: How Medialine developers authenticate to the platform — Gitea via Git Credential Manager (browser sign-in, no token), plus the two tasktool-issued tokens for the MCP servers and Jenkins. Minting, rotating, revoking, troubleshooting.
---

# Medialine developer credentials

Three systems, two tokens, one browser sign-in:

| System | How you authenticate | Env var |
|---|---|---|
| **Gitea** (git clone/push, plugin marketplace) | Git Credential Manager opens the browser once; you sign in with Entra. No token. | none |
| **MCP servers** (diag, gitea, jenkins, plugin, registry, ext-api) | tasktool-issued bearer `mlmcp_…` | `MEDIALINE_MCP_TOKEN` |
| **Jenkins** (mcp-jenkins, raw Jenkins API) | tasktool-issued token `mljenkins_…` | `MEDIALINE_JENKINS_TOKEN` |

Tasktool stores only the sha256 hash of each token. Plaintext is shown ONCE at mint time. The Jenkins token is also created in Jenkins (admin-mediated) so revocation cascades.

## One-time setup

1. **Gitea account** — open <https://gitea.medialine.com>, click *Sign in with Medialine Entra ID*. This creates the account.
2. **Get promoted to developer** — an admin sets your `role` to `developer` in `/admin/users` and adds your Gitea account to the `medialine` organisation. Until both are done, repositories show as `not found`.
3. **Save the git login** — in a normal terminal: `git ls-remote https://gitea.medialine.com/medialine/claude-plugin-platform.git`. The browser opens; sign in. GCM stores the OAuth token; from now on git works from any tool, including Claude Code.
4. **Tokens** — on `/dev/onboarding` click *Generate my tokens* and run the script it shows:

   **Windows (PowerShell, persistent for your user)**:
   ```powershell
   [Environment]::SetEnvironmentVariable("MEDIALINE_MCP_TOKEN",     "mlmcp_…",     "User")
   [Environment]::SetEnvironmentVariable("MEDIALINE_JENKINS_TOKEN", "mljenkins_…", "User")
   ```

   **macOS / Linux** — append to `~/.zshrc` or `~/.bashrc`:
   ```sh
   export MEDIALINE_MCP_TOKEN="mlmcp_…"
   export MEDIALINE_JENKINS_TOKEN="mljenkins_…"
   ```

5. **Fully quit and restart VS Code / the terminal** so the new env vars are inherited (a window reload is not enough).
6. **Verify** — the *Environment checks* on `/dev/onboarding`: Gitea account found, recent sign-in, both tokens active, six MCP servers reachable.

## Rotating tokens

- `/dev/onboarding` → *Regenerate my tokens* revokes both and issues new ones (other machines stop working until re-run). *Set up another machine* mints a parallel set without revoking anything.
- Swap the env var, restart the terminal / VS Code.
- Revocation takes effect within ~60 s (validate-result cache TTL).

## Where each credential is checked

- **Gitea**: git sends the OAuth token GCM stored. Gitea records the push under *your* account. GCM renews it in the browser when the refresh token (30 days) has expired.
- **MCP bearer**: every `/mcp` request to `https://tasktool.medialine.com/mcp/<slug>/mcp` carries it; the servers call `tasktool /api/dev-credentials/validate` (60 s cache). Today mcp-gitea then talks to Gitea with a shared service token — a later phase makes it act as you.
- **Jenkins token**: same validate path for mcp-jenkins; also usable for raw Jenkins API (`curl -u <you>:mljenkins_…`).

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `could not read Username … terminal prompts disabled` when adding the marketplace | git has no saved Gitea login | run `git ls-remote …` in a normal terminal once (browser sign-in) |
| git asks for username + password instead of opening the browser | an old `credential.https://gitea.medialine.com.provider = generic` or `http.….extraheader` setting | `git config --global --unset credential.https://gitea.medialine.com.provider` and `--unset http.https://gitea.medialine.com/.extraheader`, retry |
| repository `not found` although signed in | account not yet in the `medialine` organisation | ask an admin for the developer role |
| `401 missing_or_invalid_authorization_header` from `/mcp` | env var not set in the shell that launched Claude Code | set it, fully restart |
| `401 invalid_or_revoked_token` | token revoked or never minted — check `/dev/onboarding` | regenerate |
| All 6 servers fail simultaneously | tasktool-backend down | check `/api/health` |

## Never do this

- Never paste a token into git's password prompt and never set `MEDIALINE_GITEA_PAT`: tasktool no longer issues Gitea tokens, and the old ones were owned by the Gitea admin account, so pushes made with them show up as `admin`. If the onboarding page warns about an old Gitea token, remove it from your machine and revoke it there.

## Related skills
- [[medialine-platform-services]] — overall service map
- [[diag-api]] — using your MCP bearer to read prod logs through mcp-diag
