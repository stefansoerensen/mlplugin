---
name: auth-integration
description: Authentication and SSO integration patterns for Medialine apps with TaskTool platform — RS256-only verification of platform JWTs with the mounted public key, fail closed
user-invocable: false
---

# Authentication Integration (RS256-only TaskTool SSO)

Medialine apps do **not** log users in. The platform does: auth-service /
TaskTool authenticate the user against Entra ID and issue a **platform JWT
signed with RS256**. Every app only **verifies** that token with the platform
**public key**. An app can check a token but can never mint one, so a
compromised app cannot impersonate a user in any other app.

This is the shape the TaskTool app skeleton generates. Copy it; do not invent
a variant.

## Architecture

```
User → TaskTool portal (Entra ID login via auth-service)
     → launches https://<slug>.tasktool.medialine.com/?token=<platform JWT>
     → frontend stores it as `tasktool_token`, strips it from the URL
     → every API call: Authorization: Bearer <token>
     → backend verifies RS256 with /run/secrets/jwt_public_key → 200 or 401

Graph API access:
  App backend → TaskTool /api/graph/* (forwarding the user's token) → Microsoft Graph
```

There is exactly one mode. No local login, no dev users, no second algorithm.

## Rules

1. **RS256 only.** `algorithms=["RS256"]` — a list with exactly that one entry,
   hardcoded. Never read the algorithm from config or from the token header.
2. **Public key only.** From `JWT_PUBLIC_KEY` (PEM or file path) or the Docker
   secret mount `/run/secrets/jwt_public_key`. Apps never hold a private key or
   a shared secret.
3. **Fail closed.** No key configured → every authenticated request gets 401.
   Never "skip verification", never fall back to anything.
4. **Signature is the trust anchor.** Do not branch on `iss` (or any other
   claim) to pick a verification path. A token either verifies with the
   platform key or it is rejected.
5. **Identity, not authorization.** The token carries `sub`, `entra_id`,
   `email`, `name`, `groups` (only `SG_` security groups), `exp`, `iat`,
   `jti`. App roles (admin etc.) live in the app's own users table, looked up
   by `entra_id` or `email`. Do not consume the legacy `is_admin` claim in new code.

## Backend (FastAPI)

### Settings — `app/core/config.py`

```python
from pathlib import Path
from typing import Optional

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    APP_SLUG: str = "my-app"
    # RS256 public key: PEM content or a file path. In prod it's mounted at
    # /run/secrets/jwt_public_key. Apps only ever get the PUBLIC key, so they
    # can verify platform tokens but never forge them. No shared-secret fallback.
    JWT_PUBLIC_KEY: Optional[str] = None

    @property
    def jwt_public_key_content(self) -> Optional[str]:
        """Resolve the RS256 public key from env/PEM, file path, or Docker secret."""
        val = self.JWT_PUBLIC_KEY
        if val:
            if val.startswith("/") or val.startswith("C:"):
                p = Path(val)
                return p.read_text().strip() if p.exists() else None
            return val
        secret = Path("/run/secrets/jwt_public_key")
        if secret.exists():
            return secret.read_text().strip()
        return None


settings = Settings()
```

### Auth dependency — `app/core/auth.py`

```python
"""TaskTool SSO dependency.

Accepts the platform JWT as a Bearer header OR the `access_token` cookie.
Verification is RS256 with the platform PUBLIC key. No fallback: a token
without a valid platform signature is rejected.
"""
from fastapi import HTTPException, Request, status
from jose import JWTError, jwt

from app.core.config import settings


def _decode(token: str) -> dict:
    # RS256 with the platform public key — the single trust anchor. No fallback.
    pub = settings.jwt_public_key_content
    if not pub:
        raise JWTError("JWT public key not configured — cannot verify tokens")
    return jwt.decode(token, pub, algorithms=["RS256"], options={"verify_aud": False})


async def get_current_user(request: Request) -> dict:
    token = None
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        token = auth[7:]
    if not token:
        token = request.cookies.get("access_token")
    if not token:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not authenticated")
    try:
        return _decode(token)
    except JWTError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or expired token")
```

Use `Depends(get_current_user)` on every protected route. If the app keeps a
local users table (for app roles), upsert the row from the verified claims
*after* `_decode` succeeded — never before, never instead.

`/api/auth/me` just returns the verified claims (plus the app-local role):

```python
@router.get("/api/auth/me")
async def me(user: dict = Depends(get_current_user)) -> dict:
    return {"sub": user["sub"], "email": user.get("email"), "name": user.get("name")}
```

There is no `/api/auth/login` endpoint. Login happens at the portal.

## Frontend (React)

### Token handoff — `src/services/api.ts`

```typescript
import axios from 'axios'

// TaskTool SSO handoff: the portal launches this app with the platform JWT in
// the URL (?token=...). Capture it once on load, persist it, and strip it from
// the URL so it isn't left in history or copied into shared links. The
// access_token cookie is NOT present on the app subdomain, so relying on it
// alone leaves every portal launch unauthenticated.
const TOKEN_KEY = 'tasktool_token'

;(() => {
  const params = new URLSearchParams(window.location.search)
  const handoff = params.get('token')
  if (handoff) {
    localStorage.setItem(TOKEN_KEY, handoff)
    params.delete('token')
    const qs = params.toString()
    window.history.replaceState(
      {},
      '',
      window.location.pathname + (qs ? `?${qs}` : '') + window.location.hash,
    )
  }
})()

// Same-origin: nginx proxies /api/* to the backend.
export const api = axios.create({
  baseURL: '/api',
  withCredentials: true,
})

// Send the handoff JWT as a Bearer header. The backend accepts Bearer OR the
// access_token cookie (see get_current_user).
api.interceptors.request.use((config) => {
  const token = localStorage.getItem(TOKEN_KEY)
  if (token) config.headers.set('Authorization', `Bearer ${token}`)
  return config
})

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY)
}
```

On a 401 (expired/invalid token) clear `tasktool_token` and send the user back
to the portal (`https://tasktool.medialine.com`) to relaunch the app. There is
no local `/login` page to redirect to. Components that need the raw token
(e.g. the assistant widget) read it via `getToken()`, not a different key.

## Production compose — `docker-compose.prod.yml`

```yaml
services:
  backend:
    environment:
      APP_SLUG: my-app
      # No shared JWT secret and no auth-mode switch: the platform issues
      # tokens, the app only verifies them with the public key below.
    volumes:
      # Platform RS256 PUBLIC key. The private key stays on the signers
      # (auth-service / tasktool).
      - /opt/medialine/infrastructure/secrets/jwt_public_key.pem:/run/secrets/jwt_public_key:ro
```

Guard it in the app's Jenkinsfile convention-check stage:

```bash
grep -q 'jwt_public_key' docker-compose.prod.yml \
  || { echo "FAIL: RS256 public key is not mounted"; exit 1; }
# Only assignments (line start + colon), so explanatory comments don't trip it.
! grep -qE '^[[:space:]]*(JWT_SECRET_KEY|AUTH_MODE):' docker-compose.prod.yml \
  || { echo "FAIL: shared secret / auth mode in compose"; exit 1; }
```

## Tests — `backend/tests/conftest.py`

Tests exercise the real RS256 path with an ephemeral keypair generated per run.
Nothing is checked in, nothing is shared.

```python
import os

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

# Throwaway keypair for the test run. The app verifies with JWT_PUBLIC_KEY; the
# `sign_token` fixture mints tokens with the private half (as TaskTool would).
# Set before Settings loads.
_test_jwt_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
_test_jwt_private_pem = _test_jwt_key.private_bytes(
    serialization.Encoding.PEM,
    serialization.PrivateFormat.PKCS8,
    serialization.NoEncryption(),
).decode()
os.environ.setdefault(
    "JWT_PUBLIC_KEY",
    _test_jwt_key.public_key()
    .public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    .decode(),
)


@pytest.fixture
def sign_token():
    """Mint an RS256 platform SSO token for tests (as TaskTool would)."""
    from jose import jwt

    def _sign(claims: dict) -> str:
        return jwt.encode(claims, _test_jwt_private_pem, algorithm="RS256")

    return _sign
```

Worth having in every app: a test that a token signed with a *different* RSA
key is rejected, and one that a missing public key yields 401 (fail closed).
If you also assert that an HMAC-signed token is rejected, that test line needs
the marker `# rs256-guard: allow` — the plugin's write hook blocks HMAC JWT
patterns in code otherwise.

## Graph API access (via TaskTool)

Apps access Microsoft Graph through TaskTool's proxy, forwarding the user's
platform token:

```python
import httpx
from app.core.config import settings


class GraphClient:
    def __init__(self, user_token: str):
        self.base_url = f"{settings.TASKTOOL_API_URL}/api/graph"
        self.headers = {"Authorization": f"Bearer {user_token}"}

    async def get_manager(self, email: str | None = None) -> dict | None:
        url = f"{self.base_url}/me/manager" if not email else f"{self.base_url}/user/{email}/manager"
        async with httpx.AsyncClient() as client:
            resp = await client.get(url, headers=self.headers)
            return resp.json() if resp.status_code == 200 else None
```

## Environment variables

```bash
APP_SLUG=my-app
# Optional override; normally unset in prod (key comes from the secret mount).
# JWT_PUBLIC_KEY=/run/secrets/jwt_public_key
TASKTOOL_API_URL=http://tasktool-backend:8000
```

## Never

These are the patterns the old "dual-mode" skill taught. Every one of them is a
finding in review, and the code/config ones are blocked by the plugin's
`block-hs256` write hook:

- **HS256 / HS384 / HS512** (any HMAC algorithm) for platform tokens — to decode *or* to mint.
- **`JWT_SECRET_KEY` / `jwt_secret_key`** in app code, `.env*`, compose, Jenkinsfile or Docker secrets.
- The **`dev-secret-key-…` dummy string** or any other default/fallback secret.
- **Shared secrets** between apps and the platform, of any name.
- **Algorithm fallback**: a second entry in `algorithms=[...]`, algorithm from
  config, "RS256 if key present else …", or reading `alg` from the token header.
- **`verify_signature: False`** (or `jwt.get_unverified_claims`) for authentication.
- **Local password login / hardcoded dev users** (`DEV_USERS`, admin/test accounts),
  an `/api/auth/login` endpoint, an auth-mode switch (`AUTH_MODE=local`).
- **auth-mock** services or a `docker-compose.dev.yml` auth stack — development is cloud-only.
- **Trusting a claim** (`iss == "tasktool"`, `is_admin`) instead of the signature.
- A local **`/login` redirect** or a token key other than `tasktool_token`.

## Migrating an old app

Older apps (and older copies of this skill) have a dual-mode setup. To migrate:

1. **Backend:** replace the decode with `_decode` above. Delete the HMAC branch,
   the shared-secret setting, the issuer switch, the dev-user dict and the
   local login endpoint — delete, don't keep "for dev".
2. **Compose / infra:** remove the shared-secret env var and any
   `jwt_secret_key` Docker secret from `docker-compose.prod.yml`; add the
   `jwt_public_key.pem` mount. Remove the auth-mode env var.
3. **Frontend:** switch to the `?token=` handoff with `tasktool_token`; delete the
   login page, the login form and the `/login` redirect.
4. **Tests:** replace fixtures that minted HMAC tokens with the ephemeral RSA
   keypair + `sign_token` fixture.
5. **Jenkinsfile:** remove any test-secret env var; add the compose guard above.
6. **App-minted sessions:** only if the app *genuinely* issues its own
   sessions (not platform identity — e.g. a device or kiosk token), it may have
   its own per-app secret for that, stored as an app-specific secret, never
   named like the platform one, never accepted by `get_current_user`, and never
   shared with any other service. If you are unsure, it doesn't.
