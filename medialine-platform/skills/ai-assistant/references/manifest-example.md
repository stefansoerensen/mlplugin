# Worked example: `assistant_tools.py`

Extracted from `medialine/leads-united`
(`backend/app/api/assistant_tools.py`), the first production consumer of
assistant-service. Adapt the shape; don't copy the domain content.

## Module docstring — state the contract

```python
"""Read-only data callbacks + manifest for the platform assistant-service.

The assistant-service calls back into this app at /api/assistant-tools/*
on behalf of an authenticated user (passing the user's JWT) to look up
upload/lead/match details and to fetch this app's manifest (glossary +
tool list + action list).

All endpoints are read-only. Mutations the assistant proposes are
executed via the *existing* app endpoints when the user clicks Confirm
on an action card in the widget — the receiving endpoint sees a normal
authenticated call, audit-logged the same as a manual click.
"""
```

## Router + gate

```python
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.services import settings_service

router = APIRouter(prefix="/api/assistant-tools", tags=["assistant-tools"])


async def _check_assistant_enabled(user: dict, db: AsyncSession) -> None:
    enabled = await settings_service.get_value(db, "assistant_enabled")
    if not enabled:
        raise HTTPException(status_code=403, detail="Assistant disabled for this app")
    visible_to_all = await settings_service.get_value(db, "assistant_visible_to_all")
    if not user.get("is_admin") and not visible_to_all:
        raise HTTPException(
            status_code=403, detail="Assistant not visible to non-admin users in this app"
        )
```

## The manifest

Note how much of the payload is *glossary*. That ratio is correct — the tool
list is mechanical, the vocabulary is what makes answers right.

```python
_MANIFEST: dict = {
    "app_slug": "leads-united",
    "app_name": "Leads United",
    "app_description": (
        "Lead 2 cash: upload a list of companies, match them to the MDM (Master Data "
        "Management) via Boomi DataHub, accept/reject the suggested matches, and "
        "export the result."
    ),
    "version": "1",
    "glossary": [
        {
            "term": "MDM",
            "definition": "Master Data Management. The Boomi DataHub system that holds Medialine's authoritative company/account records.",
        },
        {
            "term": "Mandant",
            "definition": "A Medialine business unit (e.g. FIM1, ITKD, SEC1, MLAG). Every winline account belongs to one mandant; a single company may have accounts in several.",
        },
        {
            "term": "confidence score",
            "definition": "0.0–1.0 probability that an MDM candidate is the right match for the lead. Computed by the Fellegi-Sunter probabilistic ranker in match_ranker. Above 0.8 is high, 0.5–0.8 medium, below 0.5 weak.",
        },
        {
            "term": "auto-accept",
            "definition": "An admin setting (off by default) that auto-accepts a match if exactly one candidate scores at or above the threshold (default 0.95) and the lead has no other match yet.",
        },
        # … 6 more terms: KB, re-search, address enrichment, quick-search
        #   export, export limit, audit log
    ],
    "tools": [
        {
            "name": "lookup_upload",
            "description": "Return row count, matched count, status, column mapping, and uploader of one upload by its UUID.",
            "params_schema": {
                "type": "object",
                "properties": {"upload_id": {"type": "string", "description": "Upload UUID"}},
                "required": ["upload_id"],
            },
        },
        {
            "name": "read_setting",
            "description": "Return the current value of one admin setting (e.g. match_auto_accept_threshold, quick_search_max_export). Admin-only.",
            "params_schema": {
                "type": "object",
                "properties": {"key": {"type": "string", "description": "Setting key"}},
                "required": ["key"],
            },
        },
        # … lookup_match, lookup_lead
    ],
    "actions": [
        {
            "name": "trigger_match",
            "description": "Run MDM matching for all leads in an upload that don't have an accepted match yet.",
            "params_schema": {
                "type": "object",
                "properties": {"upload_id": {"type": "string"}},
                "required": ["upload_id"],
            },
            "http_method": "POST",
            "path": "api/uploads/{upload_id}/match",
        },
        {
            "name": "accept_match",
            "description": "Accept one of the suggested MDM matches for a lead.",
            "params_schema": {
                "type": "object",
                "properties": {"lead_id": {"type": "string"}, "match_id": {"type": "string"}},
                "required": ["lead_id", "match_id"],
            },
            "http_method": "POST",
            "path": "api/leads/{lead_id}/accept-match",
        },
        # … remap_column (PATCH), re_search_lead (POST)
    ],
}


@router.get("/manifest")
async def get_manifest(
    user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Return this app's assistant manifest. Gated by the per-app
    `assistant_enabled` setting + role visibility."""
    await _check_assistant_enabled(user, db)
    return _MANIFEST
```

Every `{placeholder}` in an action `path` must correspond to a key in that
action's `params_schema`. The dispatcher substitutes matching keys into the path
and sends the leftovers as the request body.

## A tool callback

GET, query params, gate first, **ownership check second**:

```python
@router.get("/tools/lookup_upload")
async def lookup_upload(
    upload_id: UUID = Query(...),
    user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    await _check_assistant_enabled(user, db)
    upload = await db.get(Upload, upload_id)
    if not upload:
        raise HTTPException(status_code=404, detail="Upload not found")
    if not user.get("is_admin") and upload.uploaded_by != user.get("email"):
        raise HTTPException(status_code=403, detail="Not your upload")
    return {
        "id": str(upload.id),
        "filename": upload.filename,
        "status": upload.status,
        "row_count": upload.row_count,
        "matched_count": upload.matched_count,
        "uploaded_by": upload.uploaded_by,
        "column_mapping": upload.column_mapping,
        "headers": upload.headers,
        "created_at": upload.created_at.isoformat(),
    }
```

Points worth copying:

- **Typed path/query params** (`UUID`, `Query(..., min_length=1, max_length=100)`) —
  the LLM supplies these values, so validate them like any untrusted input.
- **Explicit return dicts**, not ORM objects. You choose exactly what the model
  sees; don't leak columns by accident.
- **`.isoformat()` on datetimes** — the result is JSON-serialized into the next
  chat turn.
- **Traverse to the owner** when the entity doesn't carry it directly (a match →
  its lead → its upload → `uploaded_by`).
- **Admin-only tools re-check** `is_admin` on top of the shared gate, as
  `read_setting` does.

## Frontend admin toggles

Both settings need UI in the app's admin page, with i18n:

```ts
settings_assistant: 'Platform AI Assistant',
settings_assistant_desc: 'Floating ✨ launcher + ⌘-K spotlight that answers questions, looks up records, and proposes actions for you to confirm.',
settings_assistant_visible_to_all: 'Visible to non-admin users',
settings_assistant_visible_to_all_desc: 'When off, only admins see the launcher. Turn on once you trust the answers.',
```
