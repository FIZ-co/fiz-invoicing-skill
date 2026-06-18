#!/usr/bin/env bash
#
# validate.sh — reproducible checks for the fiz-invoicing skill.
# Run locally (`make check` or `bash scripts/validate.sh`) and in CI.
#
# Checks:
#   1. SKILL.md has YAML frontmatter with required `name` + `description`
#   2. SKILL.md sources bundled scripts via ${CLAUDE_SKILL_DIR} (not a bare
#      relative path, which would not resolve from the session cwd)
#   3. agents/openai.yaml parses and respects the Codex UI metadata limits
#   4. shell syntax of every *.sh (bash -n, and zsh -n if zsh is present)
#   5. fiz.sh returns 0 on HTTP 2xx and non-zero on 4xx/5xx (mock server)
#
# No third-party deps: uses python3 (stdlib only) for YAML-ish parsing + the
# mock HTTP server, and curl (which the helper itself needs).
#
# Run it under bash (`make check`). The mock-HTTP check (4) needs to spawn a
# local server and reach it over loopback; sandboxes that block subprocess exec
# or loopback networking will skip it. CI (Ubuntu, bash) runs it in full.

# No `set -e`/`pipefail`: this script reports failures via `fail`/exit code, and
# must keep running through all checks even when individual commands return
# non-zero (that's exactly what several checks assert).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$ROOT/fiz-invoicing"
fail=0
skipped=0
pass() { printf '  ok   %s\n' "$1"; }
err()  { printf '  FAIL %s\n' "$1"; fail=1; }
skip() { printf '  skip %s\n' "$1"; skipped=$((skipped + 1)); }

echo "== 1. SKILL.md frontmatter =="
python3 - "$SKILL_DIR/SKILL.md" "$ROOT/README.md" <<'PY' && pass "SKILL.md frontmatter (name, description; compatibility recorded)" || err "SKILL.md frontmatter"
import sys, re
txt = open(sys.argv[1], encoding="utf-8").read()
readme = open(sys.argv[2], encoding="utf-8").read()
m = re.match(r"^---\n(.*?)\n---\n", txt, re.S)
if not m: sys.exit("no frontmatter block")
body = m.group(1)
# top-level keys are at column 0 (block-scalar continuation lines are indented)
keys = set(re.findall(r"^([A-Za-z0-9_-]+):", body, re.M))
missing = [k for k in ("name", "description") if k not in keys]
if missing: sys.exit("missing required key(s): " + ", ".join(missing))
# The Agent Skills standard requires only name+description. Any extra key is a
# runtime extension (e.g. Claude Code's `allowed-tools`); if we use one, the
# README must declare the skill Claude-Code-first so the compatibility stance is
# explicit and doesn't drift.
STANDARD = {"name", "description", "when_to_use", "license"}
extensions = sorted(keys - STANDARD)
if extensions and "Claude-Code-first" not in readme:
    sys.exit("frontmatter uses extension key(s) %s but README does not declare the skill Claude-Code-first" % extensions)
PY

echo "== 2. script-sourcing convention =="
# Bundled scripts must be referenced via ${CLAUDE_SKILL_DIR} (commands run from
# the session cwd, not the skill dir). A bare relative `source scripts/fiz.sh`
# would break in real use — guard against re-introducing that regression.
if grep -q 'CLAUDE_SKILL_DIR}/scripts/fiz.sh' "$SKILL_DIR/SKILL.md"; then
  if grep -Eq '^\s*source +scripts/fiz\.sh' "$SKILL_DIR/SKILL.md"; then
    err "SKILL.md sources scripts/fiz.sh by bare relative path (use \${CLAUDE_SKILL_DIR})"
  else
    pass "SKILL.md sources the helper via \${CLAUDE_SKILL_DIR}"
  fi
else
  err "SKILL.md does not reference \${CLAUDE_SKILL_DIR}/scripts/fiz.sh"
fi

echo "== 3. agents/openai.yaml =="
python3 - "$SKILL_DIR/agents/openai.yaml" <<'PY' && pass "openai.yaml structure + UI metadata limits" || err "openai.yaml"
import sys, re
txt = open(sys.argv[1], encoding="utf-8").read()
# minimal structural checks without PyYAML
if "interface:" not in txt: sys.exit("missing interface:")
if "policy:" not in txt: sys.exit("missing policy:")
def field(name):
    m = re.search(rf'^\s*{name}:\s*"(.*?)"\s*$', txt, re.M)
    return m.group(1) if m else None
dn = field("display_name")
sd = field("short_description")
if not dn: sys.exit("missing display_name")
if not sd: sys.exit("missing short_description")
# Codex recommends a concise short_description (<= 64 chars).
if len(sd) > 64: sys.exit(f"short_description too long: {len(sd)} > 64")
dp = field("default_prompt")
if dp and "$fiz-invoicing" not in dp: sys.exit("default_prompt should reference $fiz-invoicing")
PY

echo "== 4. shell syntax =="
while IFS= read -r f; do
  if bash -n "$f" 2>/dev/null; then pass "bash -n ${f#$ROOT/}"; else err "bash -n ${f#$ROOT/}"; fi
  if command -v zsh >/dev/null 2>&1; then
    zsh -n "$f" 2>/dev/null && pass "zsh -n  ${f#$ROOT/}" || err "zsh -n ${f#$ROOT/}"
  fi
done < <(find "$ROOT" -name '*.sh' -not -path '*/.git/*')

echo "== 5. fiz.sh HTTP status handling =="
HELPER="$SKILL_DIR/scripts/fiz.sh"
# shellcheck disable=SC1090
source "$HELPER"

# Missing-key guard needs no network. Assert it returns non-zero AND prints the
# expected message (a shell crash under set -u would fail the message check).
msg="$( ( unset FIZ_API_KEY; fiz GET /x ) 2>&1 1>/dev/null )"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$msg" | grep -q "FIZ_API_KEY is not set"; then
  pass "missing FIZ_API_KEY -> non-zero with helper message"
else
  err "missing FIZ_API_KEY: rc=$rc msg=[$msg]"
fi

if ! command -v python3 >/dev/null 2>&1; then
  skip "python3 not found — mock HTTP status checks"
else
  PORT=8765
  python3 - "$PORT" <<'PY' &
import sys, http.server
port = int(sys.argv[1])
class H(http.server.BaseHTTPRequestHandler):
    def _go(self):
        code = int(self.path.strip("/").split("/")[-1] or 200)
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.end_headers(); self.wfile.write(b'{"message":"mock"}')
    do_GET = do_POST = _go
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
  SRV=$!
  trap 'kill $SRV 2>/dev/null' EXIT
  ready=0
  for _ in $(seq 1 30); do
    curl -s "http://127.0.0.1:$PORT/200" >/dev/null 2>&1 && { ready=1; break; }
    sleep 0.2
  done
  if [ "$ready" -ne 1 ]; then
    skip "mock server did not start — HTTP status checks"
  else
    export FIZ_API_KEY="fiz_api_test"
    export FIZ_API_URL="http://127.0.0.1:$PORT"
    fiz GET /200 >/dev/null 2>&1 && pass "HTTP 200 -> exit 0"          || err "HTTP 200 should exit 0"
    fiz GET /400 >/dev/null 2>&1 && err "HTTP 400 should be non-zero"  || pass "HTTP 400 -> non-zero"
    fiz GET /500 >/dev/null 2>&1 && err "HTTP 500 should be non-zero"  || pass "HTTP 500 -> non-zero"

    # Run the helper under a REAL zsh process (not just `zsh -n`). This is what
    # catches zsh-only runtime bugs — e.g. a `local path=...` clobbering $PATH,
    # or set -u failures — that syntax checks miss.
    if command -v zsh >/dev/null 2>&1; then
      if zsh -c "set -u; source '$HELPER'; export FIZ_API_KEY=t FIZ_API_URL='http://127.0.0.1:$PORT'; fiz GET /200 >/dev/null 2>&1" 2>/dev/null; then
        pass "zsh runtime: GET 200 -> exit 0"
      else
        err "zsh runtime: GET 200 should exit 0 (zsh-only bug?)"
      fi
      zsh -c "set -u; source '$HELPER'; export FIZ_API_KEY=t FIZ_API_URL='http://127.0.0.1:$PORT'; fiz GET /404 >/dev/null 2>&1" 2>/dev/null \
        && err "zsh runtime: GET 404 should be non-zero" \
        || pass "zsh runtime: GET 404 -> non-zero"
    fi
  fi
  kill "$SRV" 2>/dev/null || true
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "Some checks FAILED."
elif [ "$skipped" -ne 0 ]; then
  echo "All non-skipped checks passed ($skipped skipped — run in CI / a network-capable shell for full coverage)."
else
  echo "All checks passed."
fi
exit "$fail"
