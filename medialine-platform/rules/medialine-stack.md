---
paths:
  - "**/*"
---

# Approved Technology Stack (MANDATORY)

You MUST use ONLY the following technologies. Do NOT introduce alternatives without explicit approval.

## Backend
- FastAPI 0.115+
- Python 3.11+
- SQLAlchemy 2.0 (async, declarative style)
- Pydantic v2
- psycopg v3 (via asyncpg or psycopg driver)
- Alembic (migrations)
- python-jose (JWT)
- httpx (async HTTP)
- pytest + pytest-asyncio (testing)
- MSAL (Entra ID auth, when needed)

## Frontend
- React 18
- TypeScript (strict mode)
- Vite 5
- TailwindCSS
- React Router 6+
- Axios
- Lucide React (icons)
- react-hook-form + Zod (forms)
- vitest (testing)

## Infrastructure
- Docker + docker-compose
- PostgreSQL 16
- Nginx (reverse proxy)
- Jenkins (CI/CD)
- Gitea (Git hosting)

## DO NOT USE
- Django, Flask, Express, NestJS
- Next.js, Remix, Angular, Vue (except knowledge project legacy)
- MongoDB, Redis (unless explicitly required)
- Prisma, TypeORM, Sequelize
- styled-components, CSS modules, Sass
- Redux, MobX
- Jest (use vitest instead)
- yarn, pnpm (use npm)
