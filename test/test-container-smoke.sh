#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export HARNESS_DOCKER_ROOT="$ROOT"
# shellcheck disable=SC1091
source "$ROOT/bin/lib/generations.sh"
container=$(current_agent_container_id 2>/dev/null || true)
if [[ -z "$container" ]]; then echo 'SKIP: no current running generation; container smoke not run'; exit 0; fi
docker exec "$container" true
for harness in claude codex pi vibe opencode; do
  docker exec "$container" "$harness" --version >/dev/null
  docker exec "$container" test -e "/this-is-$harness-docker-env"
  docker exec "$container" test -L "/usr/local/bin/$harness-notifier"
done
echo 'running generation container smoke: ok'
