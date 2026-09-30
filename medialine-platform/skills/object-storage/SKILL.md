---
name: object-storage
description: How to use the shared platform MinIO (S3-compatible object storage) from a Medialine app
user-invocable: false
---

# Shared Object Storage (MinIO)

Every Medialine app that needs file storage uses the **shared platform MinIO**
container `shared-minio`. **Never run a private MinIO container** — apps are
isolated by per-app users + bucket-scoped policies, not by separate instances.

It is reachable on the external Docker network `medialine_network` at
`shared-minio:9000`. The container itself is defined and operated by the
platform — an app never starts, configures or upgrades it.

This skill is self-contained: everything an app needs is below.

## When to use this skill

Use this skill any time the app needs to:
- store or serve user uploads, screenshots, generated PDFs, OCR scans, parsed-quote attachments
- expose downloadable artifacts via presigned URLs
- back up or stage files for an async pipeline

If the app does not store binary files, skip MinIO entirely.

## Step-by-step integration

### 1. Request a bucket and credentials

**This is a platform task, not an app task.** Provisioning runs against the
platform's own repository and the prod host, which an app developer cannot
reach. Ask a platform admin and state:

- the **app slug**
- whether the data is **permanent** (versioning on) or **cache/ephemeral** (off)

What you get back:

| | |
|---|---|
| Bucket | `<slug>-data` |
| MinIO user | `<slug_with_underscores>_app` |
| Policy | bucket-scoped `s3:*` — the user can ONLY touch its own bucket |
| Secret | a per-app secret file on the prod host, path given to you with the credentials |

You can derive the bucket and user name yourself from the slug; only the secret
has to be handed over.

> **Known gap.** Provisioning is a file change plus a script run today, so it
> cannot be self-service. The vector service solves the same problem properly —
> an app creates its own collection through an API call. Object storage needs
> the same, and until it has it, every new bucket costs a request. Tracked as a
> platform task; do not work around it by starting a private MinIO.

### 2. Wire the four env vars + secret into compose

**Prod (`docker-compose.prod.yml`):**
```yaml
services:
  backend:
    secrets:
      - <slug>_minio_secret
    environment:
      MINIO_ENDPOINT: shared-minio:9000
      MINIO_ACCESS_KEY: <slug_with_underscores>_app
      MINIO_BUCKET: <slug>-data
      MINIO_USE_SSL: "false"
    networks:
      - medialine_network

secrets:
  <slug>_minio_secret:
    file: /opt/medialine/infrastructure/secrets/<slug>_minio_secret.txt
```

The secret path on the prod host is handed to you together with the
credentials — it is not something you create.

**Dev (`docker-compose.yml`):** plain env vars, MINIO_SECRET_KEY from local `.env`:
```yaml
backend:
  environment:
    - MINIO_ENDPOINT=shared-minio:9000
    - MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY}
    - MINIO_SECRET_KEY=${MINIO_SECRET_KEY}
    - MINIO_BUCKET=${MINIO_BUCKET}
  networks:
    - medialine_network
networks:
  medialine_network:
    external: true
```

Both files MUST attach the backend to the external `medialine_network`.

### 3. Load the secret in the entrypoint

```bash
# entrypoint.sh
if [ -f /run/secrets/<slug>_minio_secret ]; then
    export MINIO_SECRET_KEY=$(cat /run/secrets/<slug>_minio_secret | tr -d '\n\r')
fi
```

### 4. Use the SDK in Python

Add `minio>=7.2.0` to `requirements.txt` and rebuild the container — never
`pip install` on the host (cloud-only rule).

```python
# backend/app/core/config.py
class Settings(BaseSettings):
    minio_endpoint: str = "shared-minio:9000"
    minio_access_key: str
    minio_secret_key: str
    minio_bucket: str
    minio_use_ssl: bool = False
```

```python
# backend/app/services/storage.py
from datetime import timedelta
from functools import lru_cache
from minio import Minio
from app.core.config import get_settings


@lru_cache
def get_client() -> Minio:
    s = get_settings()
    return Minio(
        s.minio_endpoint,
        access_key=s.minio_access_key,
        secret_key=s.minio_secret_key,
        secure=s.minio_use_ssl,
    )


async def put_bytes(key: str, data: bytes, content_type: str) -> str:
    import io
    s = get_settings()
    client = get_client()
    if not client.bucket_exists(s.minio_bucket):
        # Should never happen — the bucket is provisioned before the app runs.
        raise RuntimeError(f"bucket {s.minio_bucket} missing — ask the platform to provision it")
    client.put_object(s.minio_bucket, key, io.BytesIO(data), len(data), content_type=content_type)
    return key


async def presigned_get(key: str, expires=timedelta(hours=1)) -> str:
    s = get_settings()
    url = get_client().presigned_get_object(s.minio_bucket, key, expires=expires)
    # Rewrite to the proxied path so browsers go through the platform nginx
    return url.replace(f"http://{s.minio_endpoint}", "/storage")
```

### 5. Add the `/storage/` nginx route

When the backend hands out presigned URLs that start with `/storage/...`, the
platform nginx must proxy that path to MinIO:

```nginx
location /storage/ {
    set $shared_minio http://shared-minio:9000;
    proxy_pass $shared_minio/;
    proxy_http_version 1.1;
    proxy_set_header Host shared-minio:9000;        # signature requires this exact host
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_buffering off;
    client_max_body_size 25m;
}
```

The `Host shared-minio:9000` header is required — MinIO presigned-URL
signatures are bound to that hostname.

### 6. Declare the dependency in TaskTool

Add `"minio"` to `services_needed` on the app's TaskTool registry entry:

```json
{ "services_needed": ["auth", "minio"] }
```

When this is set, TaskTool's framework generator automatically emits the five
MinIO env vars into the app's `.env.example`, generated `CLAUDE.md`, and
`docker-compose.prod.yml` — no manual templating required.

## Smoke test (run inside the backend container)

```python
from minio import Minio
import os

c = Minio(os.environ["MINIO_ENDPOINT"],
          access_key=os.environ["MINIO_ACCESS_KEY"],
          secret_key=os.environ["MINIO_SECRET_KEY"],
          secure=False)

print("buckets visible:", [b.name for b in c.list_buckets()])
# Expected: exactly your app's bucket. Anything else means the policy is wrong.
```

A successful test returns one bucket — the bucket-scoped policy is the
isolation guarantee.

## Operational facts (already wired, no app-side action needed)

- **Backups** — daily per-bucket `tar.gz`, 14 generations retained. Run by the
  platform; nothing to configure in the app.
- **Metrics** — Prometheus scrapes `shared-minio:9000/minio/v2/metrics/cluster`;
  per-bucket size + request rate + error rate land in Grafana.
- **Health** — TaskTool's admin monitoring grid checks
  `shared-minio:9000/minio/health/live`.

## Don'ts

- ❌ Don't add a `minio:` service to the app's compose — there's only one shared instance.
- ❌ Don't reuse another app's credential — each app has its own bucket-scoped user.
- ❌ Don't create buckets or users via the MinIO console — the platform's own
      manifest is the source of truth. Request the change instead.
- ❌ Don't commit the secret file or paste its contents into the repo.
- ❌ Don't expose port 9001 (admin console) on prod.
- ❌ Don't put the MinIO root password into any app — apps only see their
      per-app credential, never the root.
