---
name: port-allocation
description: Port allocation conventions and current registry for Medialine platform services
user-invocable: false
---

# Port Allocation Registry

## Allocation Ranges

| Range | Purpose | Example |
|-------|---------|---------|
| `8001-8099` | App backend APIs | mietkalkulator: 8001, klar: 8006 |
| `3001-3099` | App frontends | mietkalkulator: 3001, klar: 3006 |
| `8500-8599` | Shared services | cicd-service: 8010 |
| `5432` | PostgreSQL (shared) | shared_postgres |
| `5050` | pgAdmin | infrastructure |
| `80/443` | Nginx reverse proxy | infrastructure |
| `9000/9001` | MinIO object storage (shared platform service: `shared-minio`) | infrastructure |
| `3000` | Gitea web UI | infrastructure |

## Currently Allocated Ports

| Project | Backend Port | Frontend Port | Status |
|---------|-------------|---------------|--------|
| mietkalkulator | 8001 | 3001 | Production |
| billing | 8002 | — | Production |
| pulse | 8001 | 8003 | Production |
| tasktool | 8004 | 5174 | Production |
| docai-service | 8005 | — | Development |
| klar | 8006 | 3006 | Production |
| quote-parser | 8007 | — | Development |
| cicd-service | 8010 | — | Infrastructure |
| dkv-analyser | 8008 | 3008 | Development |

## Rules for New Port Allocation

1. **Check this registry** before allocating any port
2. **Backend ports:** Use next available in 8001-8099 range
3. **Frontend ports:** Use matching number in 3001-3099 range (e.g., backend 8025 → frontend 3025)
4. **Never reuse** a port from an existing project, even if that project is stopped
5. **Register immediately** in TaskTool's platform registry after allocation
6. **Document** in the project's CLAUDE.md and docker-compose files

## Next Available Ports

Based on current allocations:
- **Next backend port:** 8009 (or 8011+)
- **Next frontend port:** 3009 (or 3011+)

## How to Register

After allocating ports, register in TaskTool:

```bash
# Via TaskTool API
curl -X POST http://localhost:8004/api/registry/apps \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "slug": "my-new-app",
    "name": "My New App",
    "backend_port": 8009,
    "frontend_port": 3009,
    "backend_container": "my-new-app-backend",
    "frontend_container": "my-new-app-frontend",
    "status": "registered"
  }'
```
