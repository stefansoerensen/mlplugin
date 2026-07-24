---
name: vector-search
description: How to add semantic search / RAG to a Medialine app via the shared vector-service (Milvus) — self-service collections, per-app + tenant isolation
user-invocable: false
---

# Vector Search / RAG (shared vector-service)

Semantic search and retrieval-augmented generation for any Medialine app, backed
by one shared **Milvus** vector database behind the **`vector-service`** gateway.
Apps **never connect to Milvus directly** — every operation goes through
`vector-service`, which authenticates the app, isolates it from other apps, and
runs multi-tenancy on its behalf.

This is fully self-service: declare the dependency, create collections on demand,
ingest and query. No manifest edits, no infra PR, no bootstrap step.

## When to use

- semantic search over documents, tickets, product data, knowledge bases
- "chat with your documents" / RAG
- embedding storage for similarity / recommendations

If you only need exact-match or SQL filtering, use PostgreSQL instead.

## Step 1 — Declare the dependency

Add `vector-service` to the app's `services_needed` in its TaskTool registry
entry:

```json
{ "services_needed": ["auth", "vector-service"] }
```

That's the whole onboarding. On the next config generation + deploy the platform
emits two env vars into the app and mints its credential:

| Env var | Value |
|---|---|
| `VECTOR_SERVICE_URL` | `http://vector-service-backend:8000` |
| `VECTOR_SERVICE_TOKEN` | the app's service token (mounted at `/run/secrets/<app>_vector_token`) |

The token is an RS256 **service token** minted by `infrastructure/vector/bootstrap.sh`.
Load it in the entrypoint like any other secret:

```bash
# entrypoint.sh
if [ -f /run/secrets/<app>_vector_token ]; then
    export VECTOR_SERVICE_TOKEN="$(tr -d '\n\r' < /run/secrets/<app>_vector_token)"
fi
```

Also add the app slug to `infrastructure/vector/apps.yaml` so bootstrap mints the
token (idempotent; the config generator emits the env var, the manifest triggers
minting).

## Step 2 — Call vector-service

Every call sends `Authorization: Bearer $VECTOR_SERVICE_TOKEN`. The app is
identified from the token — you never send an app name. Every data call carries a
`tenant_id` (your multi-tenant boundary — `project_id` / `customer_id`, or a
stable sentinel like `_product` for a global knowledge base).

```python
# backend/app/services/rag.py
import httpx
from app.core.config import get_settings

s = get_settings()
BASE = s.vector_service_url            # http://vector-service-backend:8000
HEADERS = {"Authorization": f"Bearer {s.vector_service_token}"}


async def ensure_collection(name: str, model: str = "e5-base-multilingual") -> None:
    async with httpx.AsyncClient(timeout=30) as cx:
        r = await cx.post(f"{BASE}/v1/collections", headers=HEADERS,
                          json={"name": name, "model": model})
        # 201 created, or 400 if it already exists — both are fine to ignore.


async def ingest(name: str, tenant_id: str, source_id: str, text: str) -> dict:
    async with httpx.AsyncClient(timeout=60) as cx:
        r = await cx.post(f"{BASE}/v1/collections/{name}/ingest/text", headers=HEADERS,
                          json={"tenant_id": tenant_id, "source_id": source_id, "text": text})
        r.raise_for_status()
        return r.json()


async def query(name: str, tenant_id: str, q: str, top_k: int = 8) -> list[dict]:
    async with httpx.AsyncClient(timeout=30) as cx:
        r = await cx.post(f"{BASE}/v1/collections/{name}/query", headers=HEADERS,
                          json={"tenant_id": tenant_id, "query": q, "top_k": top_k})
        r.raise_for_status()
        return r.json()["matches"]
```

### Endpoint reference

Base: `http://vector-service-backend:8000` (internal). Header: `Authorization: Bearer <token>`.

| Method | Path | Body | Use |
|---|---|---|---|
| POST | `/v1/collections` | `{name, model?, dimension?, index?, metric?}` | Create a collection (yours only) |
| GET | `/v1/collections` | — | List your collections |
| DELETE | `/v1/collections/{name}` | — | Drop a collection |
| POST | `/v1/collections/{name}/ingest/text` | `{tenant_id, source_id, text, metadata?, chunk_size?, overlap?}` | Ingest text |
| POST | `/v1/collections/{name}/ingest/file` | multipart `(file, tenant_id, source_id, metadata?)` | Ingest PDF/DOCX/TXT/MD (≤50 MB) |
| POST | `/v1/collections/{name}/query` | `{tenant_id, query, top_k?, filter?}` | Top-K, tenant-scoped |
| DELETE | `/v1/collections/{name}/tenant/{tenant_id}` | — | Purge a tenant |
| GET | `/v1/collections/{name}/tenant/{tenant_id}/stats` | — | Count |

- **Models:** `e5-base-multilingual` (768, default), `e5-large-multilingual`
  (1024), `minilm-en` (384). Or `model="external"` + `dimension` to supply your
  own vectors. Schema is locked once data is written.
- Ingest is idempotent by `source_id`. Endpoints return **503** until Milvus +
  the embedding model finish loading.

## Isolation guarantees (why this is safe)

- **Cross-app is impossible.** Collections are namespaced per app and data ops run
  as your app's own Milvus RBAC user — you cannot name or reach another app's
  collections, even by accident.
- **Cross-tenant is enforced.** `tenant_id` is mandatory; the service injects it
  into every query/delete. There is no "search all tenants".

## Don'ts

- ❌ Don't connect to Milvus (`pymilvus`) directly — always go through vector-service.
- ❌ Don't run a private Milvus or vector DB — there is one shared instance.
- ❌ Don't call any data op without `tenant_id`.
- ❌ Don't hardcode or share another app's token — each app has its own.
- ❌ Don't use the old `ext-api-service /api/ai/*` endpoints — those are being
      retired in favour of vector-service.

Deep dive: `vector-service/docs/RFC-001-managed-vector-service.md`.
