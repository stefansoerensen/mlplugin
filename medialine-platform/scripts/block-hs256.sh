#!/usr/bin/env bash
# PreToolUse(Write|Edit|MultiEdit) — block shared-secret / HMAC (HS*) platform auth.
#
# Platform JWTs are RS256. Apps verify them with the mounted PUBLIC key and
# nothing else: no shared secret, no algorithm fallback, fail closed. The old
# "dual-mode" pattern (HMAC-signed JWTs with a shared secret, dev users, local login)
# let any app that knew the secret forge a token for any other app. It keeps
# coming back because older skills, templates and apps still show it, so this
# hook stops it at the point where Claude writes it into code or config.
#
# Only code/config files are scanned. Markdown is not: docs and the plugin's
# own skills have to be able to NAME the forbidden patterns in "Never" lists.
#
# Escape hatch for a deliberate negative test (e.g. "an HMAC-signed token is
# rejected"): put the marker `rs256-guard: allow` on the same line. It is
# visible in review, which is the point.
#
# See skills/auth-integration/SKILL.md and rules/security.md.

set -uo pipefail

INPUT=$(cat)

# Fail open without jq, like the other hooks: a missing tool must not brick
# every Write on a developer machine.
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -n "$FILE" ] || exit 0

# Basename, for both / and \ separators (Windows paths arrive with either).
BASE="${FILE##*[/\\]}"
LOWER=$(printf '%s' "$BASE" | tr '[:upper:]' '[:lower:]')

case "$LOWER" in
  *.py|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.yml|*.yaml|*.j2|*.toml|*.json|*.ini|*.cfg|*.sh|*.conf) ;;
  .env|.env.*|*.env) ;;
  dockerfile|dockerfile.*|*.dockerfile|jenkinsfile|jenkinsfile.*) ;;
  *) exit 0 ;;
esac

CONTENT=$(printf '%s' "$INPUT" | jq -r '
  .tool_input.content
  // .tool_input.new_string
  // ([.tool_input.edits[]?.new_string // empty] | join("\n"))
  // empty' 2>/dev/null) || exit 0
[ -n "$CONTENT" ] || exit 0

# Assembled from pieces so this file does not match its own pattern (and the
# plugin's CI content lint does not trip over it).
H='H''S'
S='SECRET'
PATTERN="${H}(256|384|512)|JWT_${S}_KEY|jwt_$(printf '%s' "$S" | tr '[:upper:]' '[:lower:]')_key|dev-secret-key-min""imum|algorithms=\\[[^]]*${H}"

HITS=$(printf '%s\n' "$CONTENT" \
  | grep -v 'rs256-guard: allow' \
  | grep -nE "$PATTERN" \
  | head -5)

[ -n "$HITS" ] || exit 0

cat >&2 <<MSG
BLOCKED: platform auth is RS256-only (skills/auth-integration, rules/security.md)

$BASE would contain a shared-secret / HMAC JWT pattern:
$(printf '%s\n' "$HITS" | sed 's/^/  /')

Platform JWTs are verified with the mounted PUBLIC key only:
  - jwt.decode(token, public_key, algorithms=["RS256"]) -- nothing else in the list
  - key from JWT_PUBLIC_KEY or /run/secrets/jwt_public_key; missing key => reject
  - no shared JWT secret, no HMAC fallback, no dev-secret default, no local login
  - tests: ephemeral RSA keypair + sign_token fixture (see the auth-integration skill)

Migrating an old app? Delete the fallback instead of rewriting it.
Deliberate negative test (asserting such a token is REJECTED)? Add the marker
'rs256-guard: allow' on that line so the exception is visible in review.
MSG
exit 2
