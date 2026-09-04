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
#   fiz POST  /invoices  '{"dueDate":"2026-07-18T00:00:00.000Z","cae":"62010","type":"INVOICE","customerId":"...","items":[{"id":"...","quantity":1}]}'
#   fiz GET   /series
#   fiz PATCH /invoices/<id> '{"notes":"PO #118"}'
#   fiz POST  /invoices/<id>/issue
#   fiz GET   /invoices/<id>/pdf
#
# Idempotency (optional, recommended for writes you might retry): set
# FIZ_IDEMPOTENCY_KEY and it is sent as the `Idempotency-Key` header. Reuse the
# SAME key when retrying the same operation; a repeat replays the first response
# instead of executing twice.
#
# Pass the key as a LITERAL, and use the identical literal on every retry of the
# same operation. Never write `$(uuidgen)` inside a command you might repeat: it
# is re-evaluated on the retry, sends a different key, and issues a second
# document — exactly what the header is meant to prevent.
#
#   uuidgen                                   # -> 3f9a1c7e-2b64-4f10-9e83-5d2a17c4b8e6
#   FIZ_IDEMPOTENCY_KEY="3f9a1c7e-2b64-4f10-9e83-5d2a17c4b8e6" fiz POST /invoices/<id>/issue
#   FIZ_IDEMPOTENCY_KEY="3f9a1c7e-2b64-4f10-9e83-5d2a17c4b8e6" fiz POST /invoices/<id>/issue
#                                             # same key -> replay, not a second issue
#
# The per-command prefix is deliberate: it doesn't persist, so the key can't leak
# into the next, unrelated write (whose different body would earn a 422).
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
  # Opt-in idempotency: harmless on reads, and on a write it makes a retry replay
  # the first response instead of creating/issuing a second document.
  if [ -n "${FIZ_IDEMPOTENCY_KEY:-}" ]; then
    set -- "$@" -H "Idempotency-Key: ${FIZ_IDEMPOTENCY_KEY}"
  fi

  # Write the response body to a temp file and capture ONLY the HTTP status code
  # on stdout. This sidesteps a zsh quirk with nested command substitution and
  # keeps body/status cleanly separated.
  local bodyfile code
  bodyfile="$(mktemp 2>/dev/null || printf '/tmp/fiz.%s' "$$")"
  # -D dumps the response headers so a replayed idempotent response can be told
  # apart from a first execution.
  local hdrfile
  hdrfile="$(mktemp 2>/dev/null || printf '/tmp/fiz.h.%s' "$$")"
  code="$(curl "$@" -D "$hdrfile" -o "$bodyfile" -w '%{http_code}')"
  if [ -z "$code" ]; then
    rm -f "$bodyfile" "$hdrfile"
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

  # A replay means the operation had already been executed under this key — the
  # body above is the ORIGINAL response, not a new document.
  if grep -qi '^idempotent-replayed:[[:space:]]*true' "$hdrfile" 2>/dev/null; then
    echo "IDEMPOTENT-REPLAYED: this is the stored response of an earlier identical request"
  fi
  # Surface Retry-After, but say something about idempotency ONLY when the call
  # actually used it: a key was sent on a mutating request. A read, or a write
  # with no key, has no key to reuse or burn — advice about one would be noise
  # at best and misleading at worst. Beyond that the STATUS decides: reusing the
  # key is right only on 409 (first attempt still in flight); on a 5xx the key
  # is already spent, so recommending it would contradict the recovery rule and
  # invite a duplicate.
  local retry idempotent=0
  case "$method" in POST|PUT|PATCH|DELETE) [ -n "${FIZ_IDEMPOTENCY_KEY:-}" ] && idempotent=1 ;; esac
  retry="$(grep -i '^retry-after:' "$hdrfile" 2>/dev/null | tr -d '\r' | head -1 | sed 's/^[^:]*:[[:space:]]*//')"
  if [ -n "$retry" ]; then
    if [ "$idempotent" -eq 1 ]; then
      case "$code" in
        409) echo "RETRY-AFTER: ${retry}s (a request with this Idempotency-Key is in flight; retry the SAME key after this delay)" ;;
        5*)  echo "RETRY-AFTER: ${retry}s (server error: the key is already spent — verify the operation's postcondition with a GET, then use a NEW key only if it did not take effect)" ;;
        *)   echo "RETRY-AFTER: ${retry}s (server asked to wait before retrying)" ;;
      esac
    else
      echo "RETRY-AFTER: ${retry}s (server asked to wait before retrying)"
    fi
  fi
  rm -f "$hdrfile"

  # 2xx → success; anything else → non-zero exit so callers/agents must notice.
  case "$code" in
    2*) return 0 ;;
    *)  echo "error: request failed with HTTP ${code}" >&2; return 1 ;;
  esac
}
