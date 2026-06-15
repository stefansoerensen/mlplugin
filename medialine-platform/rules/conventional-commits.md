---
paths:
  - "**/*"
---

# Conventional Commits (MANDATORY)

All git commits MUST follow the format: `type(scope): description`

## Types
- `feat` — new feature or capability
- `fix` — bug fix
- `docs` — documentation only changes
- `style` — formatting, missing semicolons, etc. (no code logic change)
- `refactor` — code change that neither fixes a bug nor adds a feature
- `test` — adding or updating tests
- `chore` — maintenance tasks, dependency updates
- `ci` — CI/CD pipeline changes

## Scopes (optional but recommended)
- `backend`, `frontend`, `docker`, `db`, `auth`, `api`, `ci`, `config`

## Examples
```
feat(api): add expense CRUD endpoints
fix(auth): handle expired JWT tokens gracefully
docs: update CLAUDE.md with new endpoints
refactor(frontend): extract form validation into custom hook
test(backend): add integration tests for expense service
chore(docker): update Python base image to 3.11.9
ci: add convention compliance check to Jenkins pipeline
```

## Rules
- Description starts with lowercase
- No period at the end
- Imperative mood ("add" not "added" or "adds")
- First line max 72 characters
- Body (optional) separated by blank line for detailed explanation
