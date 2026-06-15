---
paths:
  - "**/*"
---

# Security Rules (NON-NEGOTIABLE)

- NEVER hardcode secrets, API keys, tokens, or passwords in source code
- ALL secrets MUST come from environment variables loaded via `.env` files (gitignored)
- `.env.example` MUST contain only placeholder values, never real secrets
- Input validation on EVERY API endpoint using Pydantic models
- SQL injection prevention: ALWAYS use SQLAlchemy ORM queries, NEVER construct SQL with f-strings or string concatenation
- Non-root `USER` in all production Dockerfiles
- CORS: explicit allowed origins list in production, never `["*"]`
- JWT tokens: always set expiration, validate on every request
- File uploads: validate file type and size, never trust client-provided filenames
- Rate limiting on authentication endpoints
- Never log sensitive data (passwords, tokens, API keys)
- Dependencies: pin versions in requirements.txt and package-lock.json
