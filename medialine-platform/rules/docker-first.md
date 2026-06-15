---
paths:
  - "**/*"
---

# Docker-First Rule (NON-NEGOTIABLE)

- NEVER run `pip install`, `npm install`, `yarn add`, or `pnpm add` on the host machine
- ALL dependencies are installed inside Docker containers only
- If you need a new dependency:
  1. Add it to `requirements.txt` (Python) or `package.json` (Node.js)
  2. Rebuild: `docker compose -f docker-compose.dev.yml up -d --build`
- ALL tests run inside Docker: `docker compose exec backend pytest` or `docker compose exec frontend npm test`
- ALL linting runs inside Docker: `docker compose exec backend python -m black app/`
- Use `docker compose exec` for any command that needs project dependencies
- NEVER suggest the developer install anything globally or locally outside of Docker
