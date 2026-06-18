#!/usr/bin/env bash
#
# fiz.sh — tiny curl wrapper for the FIZ Public API (https://api.fiz.co)
#
# Usage:
#   export FIZ_API_KEY="fiz_api_..."       # from https://app.fiz.co/settings/integrations
#   export FIZ_API_URL="https://api.fiz.co" # optional; this is the default
#   source "${CLAUDE_SKILL_DIR}/scripts/fiz.sh"    # Claude Code: resolves from any cwd
#   source /path/to/skill/scripts/fiz.sh           # other runtimes: absolute skill path
#
#   fiz GET  /invoices
#   fiz GET  "/customers?search=Joao"
#   fiz POST /customers '{"name":"João Silva","country":"PT"}'
#   fiz POST /invoices  '{"dueDate":"2026-07-18T00:00:00.000Z","cae":"62010","type":"INVOICE","customerId":"...","items":[{"id":"...","quantity":1}]}'
#   fiz POST /invoices/<id>/issue
#   fiz GET  /invoices/<id>/pdf
#
# Works under bash and zsh. Requires: curl. `jq` pretty-prints responses if present.
#
# IMPORTANT: prints the HTTP status and RETURNS NON-ZERO on 4xx/5xx, so a JSON
# error body (the API returns {statusCode, message, timestamp} with a real HTTP
# status) is never mistaken for success. Always check the exit code / the
# "HTTP <code>" line before treating a response as done.

fiz() {
  # NB: do NOT name a local `path` — in zsh the `path` variable is tied to $PATH,
  # so `local path=...` would clobber command lookup (curl/rm "not found").
  # Default-expand so a bodyless call (e.g. `fiz GET /invoices`) and an unset key
  # are safe even under `set -u` / `setopt NO_UNSET`.
  local method="${1:-}"
  local endpoint_path="${2:-}"
  local body="${3:-}"
  local base="${FIZ_API_URL:-https://api.fiz.co}"

  if [ -z "${FIZ_API_KEY:-}" ]; then
    echo "error: FIZ_API_KEY is not set. Set it in your environment (do NOT paste the key into chat)." >&2
    echo "       Get a key at https://app.fiz.co/settings/integrations" >&2
    return 1
  fi
  if [ -z "$method" ] || [ -z "$endpoint_path" ]; then
    echo "usage: fiz <METHOD> <PATH> [JSON_BODY]" >&2
    return 1
  fi

  # Build the curl argument list in the positional params ("$@"), which expand
  # identically in bash and zsh — avoids array 0- vs 1-indexing differences.
  set -- -sS -X "$method" "${base}${endpoint_path}" -H "x-api-key: ${FIZ_API_KEY}"
  if [ -n "$body" ]; then
    set -- "$@" -H "Content-Type: application/json" -d "$body"
  fi

  # Write the response body to a temp file and capture ONLY the HTTP status code
  # on stdout. This sidesteps a zsh quirk with nested command substitution and
  # keeps body/status cleanly separated.
  local bodyfile code
  bodyfile="$(mktemp 2>/dev/null || printf '/tmp/fiz.%s' "$$")"
  code="$(curl "$@" -o "$bodyfile" -w '%{http_code}')"
  if [ -z "$code" ]; then
    rm -f "$bodyfile"
    echo "error: curl failed (network/TLS)" >&2
    return 1
  fi

  if command -v jq >/dev/null 2>&1 && [ -s "$bodyfile" ]; then
    jq . "$bodyfile" 2>/dev/null || cat "$bodyfile"
  else
    cat "$bodyfile"
  fi
  rm -f "$bodyfile"
  echo "HTTP ${code}"

  # 2xx → success; anything else → non-zero exit so callers/agents must notice.
  case "$code" in
    2*) return 0 ;;
    *)  echo "error: request failed with HTTP ${code}" >&2; return 1 ;;
  esac
}
