---
name: vibes-conventions
description: Medialine VIBES v3 development conventions — the single source of truth for all project standards
user-invocable: false
---

# VIBES v3 Development Conventions

You are building software for Medialine AG. Every decision, every line of code, every configuration MUST follow these conventions. These are non-negotiable.

## Tech Stack (MANDATORY — no alternatives)

### Backend
- **Framework:** FastAPI 0.115+ on Python 3.11
- **ORM:** SQLAlchemy 2.0 with declarative style + async
- **Database driver:** psycopg v3 (via `postgresql+asyncpg://` or `postgresql+psycopg://`)
- **Validation:** Pydantic v2
- **Migrations:** Alembic
- **Auth:** python-jose for JWT, MSAL for Entra ID (optional)
- **HTTP client:** httpx (async)
- **Testing:** pytest + pytest-asyncio

### Frontend
- **Framework:** React 18 with TypeScript (strict mode)
- **Build tool:** Vite 5
- **Styling:** TailwindCSS (no custom CSS files, no styled-components, no CSS modules)
- **Routing:** React Router 6+
- **HTTP client:** Axios with interceptors
- **State:** React Context or Zustand (no Redux)
- **Forms:** react-hook-form + Zod
- **Testing:** vitest
- **Icons:** Lucide React

### Infrastructure
- **Containers:** Docker with docker-compose
- **Database:** PostgreSQL 16
- **Reverse proxy:** Nginx
- **Git:** Gitea (primary), GitHub (secondary)
- **CI/CD:** Jenkins with Declarative Pipeline
- **Network:** External Docker bridge `medialine_network`

## Project Structure (App Type)

```
project-root/
├── backend/
│   ├── app/
│   │   ├── __init__.py
│   │   ├── main.py              # FastAPI app, CORS, health endpoint, router includes
│   │   ├── api/
│   │   │   ├── __init__.py
│   │   │   ├── deps.py          # get_db; re-exports get_current_user from core/auth.py
│   │   │   └── {module}.py      # Route handlers per domain
│   │   ├── core/
│   │   │   ├── __init__.py
│   │   │   ├── config.py        # Pydantic Settings (incl. JWT_PUBLIC_KEY)
│   │   │   ├── auth.py          # get_current_user: RS256-only platform JWT verification
│   │   │   └── database.py      # SQLAlchemy engine, Base, SessionLocal
│   │   ├── models/              # SQLAlchemy models (one file per entity)
│   │   ├── schemas/             # Pydantic request/response schemas
│   │   └── services/            # Business logic layer
│   ├── alembic/                 # Database migrations
│   ├── tests/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── requirements.txt
├── frontend/
│   ├── src/
│   │   ├── App.tsx              # Routes, layout, providers
│   │   ├── main.tsx             # Entry point
│   │   ├── pages/               # Route-level components
│   │   ├── components/          # Reusable UI components
│   │   ├── hooks/               # Custom hooks (useAuth, etc.)
│   │   ├── services/
│   │   │   └── api.ts           # Axios instance, ?token= handoff (tasktool_token)
│   │   └── types/
│   │       └── index.ts         # ALL TypeScript interfaces (centralized)
│   ├── public/
│   ├── Dockerfile
│   ├── nginx.conf               # Production nginx for SPA
│   ├── package.json
│   ├── tsconfig.json
│   └── vite.config.ts
├── docs/
├── scripts/
├── adr/                         # Architecture Decision Records
├── .env.example                 # Placeholder values only
├── .env.prod.example            # Production template
├── .gitignore
├── CLAUDE.md                    # AI context (CRITICAL)
├── Jenkinsfile                  # CI/CD pipeline
├── Makefile                     # Common commands
├── docker-compose.yml           # App services only
├── docker-compose.prod.yml      # Production (medialine_network, jwt_public_key mount)
└── README.md
```

## Code Standards

### Python (Backend)
- Full type hints (PEP 484) on EVERY function signature
- Async/await for all I/O operations
- Pydantic models for ALL request/response validation
- FastAPI Depends() for dependency injection
- Proper error handling with HTTPException and status codes
- Logging with `logging.getLogger(__name__)`
- Docstrings on all public functions and classes
- Black formatting, isort for imports

### TypeScript (Frontend)
- `strict: true` in tsconfig.json — no exceptions
- NEVER use `any` — define proper interfaces
- ALL interfaces go in `types/index.ts` (centralized)
- Functional components with hooks only (no class components)
- TailwindCSS utility classes only (no custom CSS files)
- Axios service layer for ALL API calls (never raw fetch)
- React Router 6 for navigation

### API Design
- RESTful endpoints with proper HTTP methods
- `snake_case` for all JSON fields
- Standard error response: `{"detail": "error message"}`
- Health check at `GET /health` or `GET /api/health`
- Versioning: not required unless breaking changes
- Pagination: `?skip=0&limit=50` pattern
- Authentication: Bearer JWT in Authorization header

### Database
- PostgreSQL 16 with schema isolation per app
- `snake_case` for all table and column names
- `UUID` primary keys (uuid4)
- `created_at` and `updated_at` timestamps on every table
- Foreign key constraints with proper cascading
- Indexes on frequently queried columns
- Schema name = project slug with underscores (e.g., `expense_tracker`)

## Authentication Pattern (RS256-only TaskTool SSO)

There is one mode. The platform (auth-service / TaskTool) logs the user in and
issues an RS256-signed platform JWT; the app only verifies it:

1. The portal launches the app with `?token=<jwt>`; the frontend stores it as
   `tasktool_token`, strips it from the URL, and sends it as `Authorization: Bearer`.
2. The backend verifies with the platform **public key** (`JWT_PUBLIC_KEY` or
   the mount `/run/secrets/jwt_public_key`), `algorithms=["RS256"]` only.
   No key → 401 (fail closed).
3. Tests use an ephemeral RSA keypair + a `sign_token` fixture.

No local login, no dev users, no shared JWT secret, no HMAC algorithm, no
auth-mock. Details and the "Never" list: [`auth-integration`](../auth-integration/SKILL.md).

## Port Convention

- App backends: `8001-8099`
- App frontends: `3001-3099`
- Shared services: `8500-8599`
- Infrastructure: `5432` (PostgreSQL), `5050` (pgAdmin), `80/443` (Nginx)
- ALWAYS check TaskTool registry for available ports before allocating

## Git & Commits
- Conventional Commits: `type(scope): description`
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`
- Scopes: `backend`, `frontend`, `docker`, `db`, `auth`, `api`, `ci`
- Semantic Versioning for releases

## Security (NON-NEGOTIABLE)
- NEVER hardcode secrets in source code
- ALL secrets via environment variables from `.env` (gitignored)
- `.env.example` has placeholder values only
- Input validation on EVERY endpoint (Pydantic)
- SQL injection prevention: SQLAlchemy ORM only, never raw f-string SQL
- Non-root USER in all production Dockerfiles
- CORS properly configured (explicit origins, not `*` in production)
- Rate limiting on authentication endpoints
