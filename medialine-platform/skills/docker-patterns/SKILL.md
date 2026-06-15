---
name: docker-patterns
description: Docker-first development and deployment patterns for Medialine applications
user-invocable: false
---

# Docker Development & Deployment Patterns

ALL Medialine development happens inside Docker containers. No exceptions.

## Development Environment (docker-compose.dev.yml)

Every project ships with a self-contained dev environment that works offline:

```yaml
# docker-compose.dev.yml — runs EVERYTHING locally, no external dependencies
include:
  - infrastructure/docker-compose.infra.yml  # local PostgreSQL + auth-mock

services:
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile.dev
    volumes:
      - ./backend/app:/app/app    # Hot reload
    environment:
      DATABASE_URL: postgresql+asyncpg://postgres:dev_password@postgres-{project}:5432/{project}_db
      JWT_SECRET_KEY: dev-secret-key-minimum-32-characters-long
      AUTH_MODE: local
      DEBUG: "true"
    ports:
      - "{backend_port}:8000"
    depends_on:
      postgres-{project}:
        condition: service_healthy
    networks:
      - {project}-network

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile.dev
    volumes:
      - ./frontend/src:/app/src
      - /app/node_modules          # Exclude node_modules from mount
    environment:
      VITE_API_URL: http://localhost:{backend_port}
    ports:
      - "{frontend_port}:5173"
    networks:
      - {project}-network

networks:
  {project}-network:
    driver: bridge
```

## Production Environment (docker-compose.prod.yml)

Production uses central shared infrastructure:

```yaml
# docker-compose.prod.yml — uses shared PostgreSQL, medialine_network
services:
  backend:
    image: registry.medialine.local/{project}-backend:latest
    environment:
      DATABASE_URL: postgresql+asyncpg://postgres:${POSTGRES_PASSWORD}@shared_postgres:5432/{project}_db
      AUTH_MODE: entra
      DEBUG: "false"
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
      interval: 30s
      timeout: 3s
      start_period: 40s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - medialine_network

  frontend:
    image: registry.medialine.local/{project}-frontend:latest
    build:
      args:
        VITE_API_URL: ""   # Relative paths, proxied by Nginx
    depends_on:
      backend:
        condition: service_healthy
    networks:
      - medialine_network

networks:
  medialine_network:
    external: true
```

## Backend Dockerfile Pattern

```dockerfile
# Multi-stage build — Medialine standard
FROM python:3.11-slim AS base

RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

# Production stage
FROM base AS production
RUN useradd -m -s /bin/bash appuser
RUN chown -R appuser:appuser /app
USER appuser
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]

# Development stage
FROM base AS development
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
```

## Frontend Dockerfile Pattern

```dockerfile
# Build stage
FROM node:18-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
ARG VITE_API_URL
ENV VITE_API_URL=$VITE_API_URL
RUN npm run build

# Production stage
FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost || exit 1
CMD ["nginx", "-g", "daemon off;"]
```

## Local Infrastructure Pattern

Each project includes `infrastructure/` with:

1. **PostgreSQL** — project-specific instance (not shared_postgres in dev)
2. **Auth mock** — mimics TaskTool auth endpoints for offline development
3. **init.sql** — creates schema, seeds dev data

```yaml
# infrastructure/docker-compose.infra.yml
services:
  postgres-{project}:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: {project}_db
      POSTGRES_PASSWORD: dev_password
    volumes:
      - ./infrastructure/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql
      - pgdata-{project}:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      - {project}-network

  auth-mock:
    build: ./infrastructure/auth-mock
    environment:
      JWT_SECRET_KEY: dev-secret-key-minimum-32-characters-long
    networks:
      - {project}-network

volumes:
  pgdata-{project}:
```

## Key Rules

1. **NEVER** run package managers on host — always in containers
2. **ALWAYS** use `depends_on` with `service_healthy` condition
3. **ALWAYS** include HEALTHCHECK in production Dockerfiles
4. **ALWAYS** use non-root USER in production
5. **ALWAYS** include log rotation in production compose
6. **NEVER** mount volumes in production (bake into image)
7. Dev compose uses named volumes for database persistence
8. Use `docker compose exec` for running commands inside containers
