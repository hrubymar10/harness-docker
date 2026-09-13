#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/docker" <<'EOF'
#!/bin/bash
printf '%q ' "$@" >> "$MOCK_LOG"; printf '\n' >> "$MOCK_LOG"
if [[ "${1:-}" == ps ]]; then
  [[ "${MOCK_PS_FAIL:-0}" != 1 ]] || exit 1
  printf '%b' "${MOCK_PS_OUTPUT:-}"
  exit 0
fi
exit 1
EOF
chmod +x "$TMP/bin/docker"
export PATH="$TMP/bin:$PATH" MOCK_LOG="$TMP/docker.log" HARNESS_DOCKER_SKIP_UPDATE_CHECK=1
marker="$TMP/notice-shown"

MOCK_PS_OUTPUT=$'claude-filter-proxy|unrelated\nrandom|codex-docker\npi-docker|\nvibe-socket-proxy|other\n' \
  HARNESS_DOCKER_LEGACY_NOTICE_MARKER="$marker" "$ROOT/bin/harness-docker-ctrl" start > "$TMP/first" 2>&1 || true
[[ -f "$marker" ]]
grep -Fq 'harness-docker supersedes' "$TMP/first"
for legacy in claude-docker codex-docker pi-docker vibe-docker; do
  grep -Fqx "  docker compose -p $legacy down --rmi local" "$TMP/first"
done
if grep -Eq '(^| )compose .* down|(^| )down( |$)' "$MOCK_LOG"; then exit 1; fi

MOCK_PS_OUTPUT=$'claude-filter-proxy|claude-docker\n' HARNESS_DOCKER_LEGACY_NOTICE_MARKER="$marker" \
  "$ROOT/bin/harness-docker-ctrl" start > "$TMP/second" 2>&1 || true
if grep -Fq 'harness-docker supersedes' "$TMP/second"; then exit 1; fi

lookalike="$TMP/lookalike-marker"
MOCK_PS_OUTPUT=$'claude-filter-proxy-helper|claude-docker-next\n' HARNESS_DOCKER_LEGACY_NOTICE_MARKER="$lookalike" \
  "$ROOT/bin/harness-docker-ctrl" start > "$TMP/lookalike" 2>&1 || true
[[ ! -e "$lookalike" ]]

unreachable="$TMP/unreachable-marker"
MOCK_PS_FAIL=1 HARNESS_DOCKER_LEGACY_NOTICE_MARKER="$unreachable" \
  "$ROOT/bin/harness-docker-ctrl" start > "$TMP/unreachable" 2>&1 || true
[[ ! -e "$unreachable" ]]
if grep -Fq 'harness-docker supersedes' "$TMP/unreachable"; then exit 1; fi

echo 'legacy stack notice: ok'
