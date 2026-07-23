---
name: vector-search
description: How to use the shared platform Milvus (vector search / RAG) from a Medialine app — ingest, query, and delete embeddings via ext-api-service /api/ai/*
user-invocable: false
---

# Shared Vector Search / RAG (Milvus via ext-api-service)

Every Medialine app that needs semantic search, retrieval-augmented generation
(RAG), or embedding storage uses the **shared platform Milvus** vector database.
**Never run a private Milvus container** and **never open a direct Milvus
connection from an app** — all apps share one `shared-milvus` instance, and every
RAG operation goes through the **`ext-api-service` `/api/ai/*` gateway**, which
holds the root credentials and centralizes chunking + embedding.

Milvus is defined in `infrastructure/docker-compose.prod.yml` (prod) and
`infrastructure/docker-compose.yml` (dev), reachable on the external Docker
network `medialine_network` at `shared-milvus:19530`. The gateway is reachable
at `http://ext-api-service:8000` on the same network. Authoritative how-to with
the full background lives in
[`infrastructure/docs/SHARED-MILVUS-INTEGRATION.md`](https://gitea.medialine.com/medialine/infrastructure/src/branch/main/docs/SHARED-MILVUS-INTEGRATION.md).

## When to use this skill

Use this skill any time the app needs to:
- semantically search documents, tickets, product data, or knowledge bases
- build a RAG / "chat with your documents" feature
- store and retrieve embeddings for similarity / recommendation

If the app only needs exact-match or SQL filtering, use Postgres — not Milvus.

## The two invariants (why there is no direct Milvus access)

1. **Apps never name a collection.** The collection is resolved server-side from
   the `X-Source-App` header, so one app can never read or write another app's
   vectors. You pass your app slug; the gateway maps it to your collection.
2. **Every operation is tenant-scoped.** `tenant_id` is mandatory on every call
   and is injected into every Milvus filter as `tenant_id == "<value>"`. There
   is no "search across all tenants" — this prevents accidental cross-customer
   leakage. Use `project_id` / `customer_id` as the tenant value; for a global
   knowledge base use a stable sentinel like `_product`.

A raw Milvus client would let an app violate both. The `/api/ai/*` subset is the
whole supported surface — ingest, query, delete, count. That is everything an app
needs; collection/index/RBAC management is platform-operator concern, handled by
`infrastructure/milvus/bootstrap.sh`, not by apps.

## Step-by-step integration

### 1. Get a collection provisioned

Add an entry to `infrastructure/milvus/collections.yaml` and re-run
`infrastructure/milvus/bootstrap.sh` on the prod host (idempotent):

```yaml
apps:
  - app: <this-app-slug>
    collection: <this_app_slug>_documents  # alphanumeric + underscore ONLY, no hyphens
    partition_key: tenant_id               # always "tenant_id"
    embedding_model: e5-base-multilingual  # only supported model today
    dimension: 768                         # locked to e5-base-multilingual
    index: HNSW
    metric: COSINE
    num_partitions: 4096                   # bump only if you expect >4k tenants
```

Bootstrap creates the collection (standard schema: `source_id`, `tenant_id`,
`chunk_text`, `metadata` JSON, `embedding` dim=768, HNSW/COSINE index), plus a
per-app Milvus user + RBAC role reserved for future direct-connection use cases.
**Schema is locked once data is written** — changing `dimension` or the primary
key requires a manual drop + re-ingest.

### 2. Call `/api/ai/*` from your app

There is **no Milvus client to wire in** and no credential to mount. Your app
just makes HTTP calls to `ext-api-service`, passing `X-Source-App: <your-app-slug>`.

```python
# backend/app/services/rag_service.py
import httpx
from app.core.config import get_settings

EXT_API = get_settings().ext_api_service_url  # http://ext-api-service:8000


async def ingest_text(tenant_id: str, source_id: str, text: str, metadata: dict | None = None) -> dict:
    async with httpx.AsyncClient(timeout=60.0) as cx:
        r = await cx.post(
            f"{EXT_API}/api/ai/ingest/text",
            headers={"X-Source-App": "<your-app-slug>"},
            json={"tenant_id": tenant_id, "source_id": source_id, "text": text, "metadata": metadata},
        )
        r.raise_for_status()
        return r.json()


async def query(tenant_id: str, question: str, top_k: int = 8) -> list[dict]:
    async with httpx.AsyncClient(timeout=30.0) as cx:
        r = await cx.post(
            f"{EXT_API}/api/ai/query",
            headers={"X-Source-App": "<your-app-slug>"},
            json={"tenant_id": tenant_id, "query": question, "top_k": top_k},
        )
        r.raise_for_status()
        return r.json()["matches"]
```

### Endpoint reference

All paths are under `http://ext-api-service:8000` and require the
`X-Source-App: <your-app-slug>` header.

| Method | Path | Body | Use |
|---|---|---|---|
| POST | `/api/ai/ingest/text` | `{tenant_id, source_id, text, metadata?, chunk_size?, overlap?}` | Ingest already-extracted text. Chunked + embedded server-side. |
| POST | `/api/ai/ingest/file` | multipart `(file, tenant_id, source_id, metadata?)` | Ingest a PDF/DOCX/TXT/MD (≤50 MB); text extracted server-side. |
| POST | `/api/ai/query` | `{tenant_id, query, top_k=8, filter?}` | Top-K semantic retrieval scoped to one tenant. |
| DELETE | `/api/ai/tenant/{tenant_id}` | — | Purge every vector for a tenant. |
| GET | `/api/ai/tenant/{tenant_id}/stats` | — | `{count}` for diagnostics. |

Ingest is **idempotent by `source_id`** — re-ingesting the same document replaces
its chunks (the chunk index is appended to the primary key internally).

### Attach your backend to the network

Prod (`docker-compose.prod.yml`) and dev (`docker-compose.yml`) must attach the
backend to the external `medialine_network` so `ext-api-service:8000` resolves:

```yaml
services:
  backend:
    environment:
      EXT_API_SERVICE_URL: http://ext-api-service:8000
    networks:
      - medialine_network
networks:
  medialine_network:
    external: true
```

## Smoke test (run inside the backend container)

```bash
# 503 = pipeline still loading, 200 = ready, 404 = NOT deployed (wrong)
curl -s -o /dev/null -w "%{http_code}\n" \
  -H "X-Source-App: <your-app-slug>" \
  http://ext-api-service:8000/api/ai/tenant/_smoke/stats
```

A `400 "X-Source-App header is required"` means you forgot the header. A
`400 unknown app` means your slug isn't in `collections.yaml` yet — go back to
step 1. The gateway returns **503** until both the embedding model and Milvus
finish loading; retry shortly.

## Operational facts (already wired, no app-side action needed)

- **Backups** — daily at 02:00 UTC via the official `milvus-backup` CLI, 14
  archives retained per collection, stored in the MinIO `milvus-backup` bucket.
  Driven by cicd-service's scheduler.
- **Metrics** — Prometheus scrapes `shared-milvus:9091/metrics`; alerts
  `MilvusDown`, `MilvusHighMemory`, `MilvusBackupMissing` are pre-wired.
- **Admin** — TaskTool admin → Milvus shows health, per-collection/per-tenant
  vector counts, and backup/restore.

## Don'ts

- ❌ Don't add a `milvus:` service to the app's compose — there's one shared instance.
- ❌ Don't open a direct `pymilvus` connection from an app — go through `/api/ai/*`.
- ❌ Don't call any operation without `tenant_id` — it's the isolation boundary.
- ❌ Don't create/rename collections in Milvus directly — `collections.yaml` +
      `bootstrap.sh` is the source of truth.
- ❌ Don't tar/copy `/opt/medialine/infrastructure/data/milvus` to back it up —
      Milvus is not FS-level crash-consistent; only the backup CLI is safe.
- ❌ Don't change `embedding_model` / `dimension` after data is ingested — the
      dimension is baked into the index; it requires a drop + re-embed.
